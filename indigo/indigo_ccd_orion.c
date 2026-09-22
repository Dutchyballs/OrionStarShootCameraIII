/* Native INDIGO adapter for Orion StarShoot Solar System Color Imager III.
 * Linux gspca/ov519, USB 0e96:c001, BA81 (BGGR8). No vendor USB writes.
 * CCD_EXPOSURE is a frame-request wait, NOT calibrated sensor integration.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <math.h>
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <time.h>
#include <unistd.h>
#include <indigo/indigo_driver.h>
#include <indigo/indigo_ccd_driver.h>

#define DRIVER_NAME "indigo_ccd_orion"
#define DRIVER_VERSION 0x0001
#define CAMERA_PATH "/dev/v4l/by-id/usb-APLUX_USB2.0_PC_Camera-video-index0"
#define PRIVATE_DATA ((orion_private *)device->private_data)
#define AUTO_PROPERTY (PRIVATE_DATA->automatic)
#define RAW_PROPERTY (PRIVATE_DATA->raw_exposure)
#define MAX_BUFFERS 4

typedef struct header_update {
  indigo_property *property;
  struct header_update *next;
} header_update;

typedef struct {
  int fd;
  unsigned width, height, stride, buffer_count;
  struct { void *address; size_t length; } mapped[MAX_BUFFERS];
  unsigned char *image;
  bool streaming;
  atomic_bool cancel, controlling;
  pthread_mutex_t mutex, header_mutex;
  header_update *headers_head, *headers_tail;
  unsigned header_count;
  indigo_timer *timer, *control_timer;
  indigo_property *automatic, *raw_exposure;
} orion_private;

/* Mount metadata can arrive during capture. Apply it between frames, never
 * while the base driver is reading/reallocating the FITS keyword property. */
static void flush_headers(indigo_device *device) {
  orion_private *p = PRIVATE_DATA;
  pthread_mutex_lock(&p->header_mutex);
  header_update *head = p->headers_head;
  p->headers_head = p->headers_tail = NULL;
  p->header_count = 0;
  pthread_mutex_unlock(&p->header_mutex);
  while (head) {
    header_update *next = head->next;
    indigo_ccd_change_property(device, NULL, head->property);
    indigo_release_property(head->property);
    free(head);
    head = next;
  }
}
static void queue_header(indigo_device *device, indigo_property *property) {
  orion_private *p = PRIVATE_DATA;
  pthread_mutex_lock(&p->header_mutex);
  if (p->header_count >= 64) {
    pthread_mutex_unlock(&p->header_mutex);
    indigo_send_message(device, ALERT_PROPERTY, "Too many pending image metadata updates");
    return;
  }
  header_update *entry = indigo_safe_malloc(sizeof(*entry));
  entry->property = indigo_copy_property(NULL, property);
  entry->next = NULL;
  if (p->headers_tail) p->headers_tail->next = entry;
  else p->headers_head = entry;
  p->headers_tail = entry;
  p->header_count++;
  pthread_mutex_unlock(&p->header_mutex);
}

static int xioctl(int fd, unsigned long request, void *arg) {
  int rc;
  do { rc = ioctl(fd, request, arg); } while (rc < 0 && errno == EINTR);
  return rc;
}
static double monotonic_seconds(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}
static bool wait_until(orion_private *p, double deadline) {
  while (!atomic_load(&p->cancel) && monotonic_seconds() < deadline) {
    struct timespec pause = {0, 10000000};
    nanosleep(&pause, NULL);
  }
  return !atomic_load(&p->cancel);
}
static bool get_control(int fd, unsigned id, int *value) {
  struct v4l2_control ctrl = {.id = id};
  if (xioctl(fd, VIDIOC_G_CTRL, &ctrl) < 0) return false;
  *value = ctrl.value;
  return true;
}
static bool set_control(int fd, unsigned id, int value) {
  struct v4l2_control ctrl = {.id = id, .value = value};
  return xioctl(fd, VIDIOC_S_CTRL, &ctrl) == 0;
}
static bool usb_identity(int fd) {
  struct stat st;
  char link[128], path[4096];
  if (fstat(fd, &st) || !S_ISCHR(st.st_mode)) return false;
  snprintf(link, sizeof(link), "/sys/dev/char/%u:%u/device", major(st.st_rdev), minor(st.st_rdev));
  if (!realpath(link, path)) return false;
  for (int depth = 0; depth < 10; depth++) {
    char filename[4200]; unsigned vendor = 0, product = 0;
    snprintf(filename, sizeof(filename), "%s/idVendor", path);
    FILE *f = fopen(filename, "r");
    if (f) { int rc = fscanf(f, "%x", &vendor); fclose(f); if (rc != 1) return false; }
    snprintf(filename, sizeof(filename), "%s/idProduct", path);
    f = fopen(filename, "r");
    if (f) { int rc = fscanf(f, "%x", &product); fclose(f); if (rc != 1) return false; }
    if (vendor || product) return vendor == 0x0e96 && product == 0xc001;
    char *slash = strrchr(path, '/');
    if (!slash || slash == path) break;
    *slash = 0;
  }
  return false;
}
static bool stop_stream(orion_private *p) {
  if (!p->streaming) return true;
  enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  bool ok = xioctl(p->fd, VIDIOC_STREAMOFF, &type) == 0;
  p->streaming = false;
  return ok;
}
static void release_buffers(orion_private *p) {
  stop_stream(p);
  for (unsigned i = 0; i < p->buffer_count; i++) {
    if (p->mapped[i].address && p->mapped[i].address != MAP_FAILED)
      munmap(p->mapped[i].address, p->mapped[i].length);
    p->mapped[i].address = NULL;
  }
  p->buffer_count = 0;
  if (p->fd >= 0) {
    struct v4l2_requestbuffers req = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP};
    xioctl(p->fd, VIDIOC_REQBUFS, &req);
  }
}
static void close_camera(orion_private *p) {
  release_buffers(p);
  if (p->fd >= 0) close(p->fd);
  p->fd = -1;
}
static bool configure_format(orion_private *p, unsigned width, unsigned height) {
  release_buffers(p);
  struct v4l2_format fmt = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE};
  fmt.fmt.pix.width = width; fmt.fmt.pix.height = height;
  fmt.fmt.pix.pixelformat = V4L2_PIX_FMT_SBGGR8;
  fmt.fmt.pix.field = V4L2_FIELD_NONE;
  if (xioctl(p->fd, VIDIOC_S_FMT, &fmt) < 0) return false;
  if (fmt.fmt.pix.width != width || fmt.fmt.pix.height != height || fmt.fmt.pix.pixelformat != V4L2_PIX_FMT_SBGGR8) { errno = ENOTSUP; return false; }
  unsigned stride = fmt.fmt.pix.bytesperline ? fmt.fmt.pix.bytesperline : width;
  if (stride < width || stride > 16384 || fmt.fmt.pix.sizeimage < stride * height) { errno = EINVAL; return false; }
  struct v4l2_requestbuffers req = {.count = MAX_BUFFERS, .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP};
  if (xioctl(p->fd, VIDIOC_REQBUFS, &req) < 0) return false;
  if (req.count < 2 || req.count > MAX_BUFFERS) { errno = ENOMEM; return false; }
  p->buffer_count = req.count;
  for (unsigned i = 0; i < req.count; i++) {
    struct v4l2_buffer buf = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP, .index = i};
    if (xioctl(p->fd, VIDIOC_QUERYBUF, &buf) < 0) goto fail;
    p->mapped[i].length = buf.length;
    p->mapped[i].address = mmap(NULL, buf.length, PROT_READ | PROT_WRITE, MAP_SHARED, p->fd, buf.m.offset);
    if (p->mapped[i].address == MAP_FAILED) goto fail;
  }
  p->width = width; p->height = height; p->stride = stride;
  return true;
fail: {
  int saved = errno; release_buffers(p); errno = saved; return false;
}}
static void update_geometry(indigo_device *device) {
  orion_private *p = PRIVATE_DATA;
  CCD_INFO_WIDTH_ITEM->number.value = CCD_FRAME_WIDTH_ITEM->number.max = p->width;
  CCD_INFO_HEIGHT_ITEM->number.value = CCD_FRAME_HEIGHT_ITEM->number.max = p->height;
  CCD_FRAME_WIDTH_ITEM->number.value = CCD_FRAME_WIDTH_ITEM->number.target = p->width;
  CCD_FRAME_HEIGHT_ITEM->number.value = CCD_FRAME_HEIGHT_ITEM->number.target = p->height;
  CCD_FRAME_BITS_PER_PIXEL_ITEM->number.value = CCD_FRAME_BITS_PER_PIXEL_ITEM->number.target = 8;
}
static bool open_camera(indigo_device *device) {
  orion_private *p = PRIVATE_DATA;
  p->fd = open(CAMERA_PATH, O_RDWR | O_NONBLOCK | O_CLOEXEC);
  if (p->fd < 0) return false;
  struct v4l2_capability cap = {0};
  if (!usb_identity(p->fd)) { errno = ENODEV; goto fail; }
  if (xioctl(p->fd, VIDIOC_QUERYCAP, &cap) < 0) goto fail;
  unsigned caps = cap.capabilities & V4L2_CAP_DEVICE_CAPS ? cap.device_caps : cap.capabilities;
  if ((strcmp((char *)cap.driver, "ov519") && strcmp((char *)cap.driver, "gspca_ov519")) ||
      !(caps & V4L2_CAP_VIDEO_CAPTURE) || !(caps & V4L2_CAP_STREAMING)) { errno = ENODEV; goto fail; }
  struct v4l2_queryctrl raw = {.id = V4L2_CID_EXPOSURE}, automatic = {.id = V4L2_CID_AUTOGAIN};
  if (xioctl(p->fd, VIDIOC_QUERYCTRL, &raw) < 0 || xioctl(p->fd, VIDIOC_QUERYCTRL, &automatic) < 0) goto fail;
  if ((raw.flags | automatic.flags) & V4L2_CTRL_FLAG_DISABLED || raw.minimum != 0 || raw.maximum != 255) { errno = ENOTSUP; goto fail; }
  int auto_value, raw_value;
  if (!get_control(p->fd, V4L2_CID_AUTOGAIN, &auto_value) || !get_control(p->fd, V4L2_CID_EXPOSURE, &raw_value)) goto fail;
  indigo_set_switch(AUTO_PROPERTY, AUTO_PROPERTY->items + (auto_value ? 0 : 1), true);
  RAW_PROPERTY->items[0].number.value = RAW_PROPERTY->items[0].number.target = raw_value;
  if (!configure_format(p, CCD_MODE_PROPERTY->items[1].sw.value ? 1280 : 640, CCD_MODE_PROPERTY->items[1].sw.value ? 1024 : 480)) goto fail;
  update_geometry(device);
  return true;
fail: {
  int saved = errno; close_camera(p); errno = saved; return false;
}}

/* The timer owns the capture mutex. Abort uses the atomic flag and joins it
 * without holding that mutex, so a blocked poll cannot deadlock disconnect. */
static void capture_callback(indigo_device *device) {
  orion_private *p = PRIVATE_DATA;
  pthread_mutex_lock(&p->mutex);
  bool success = false;
  int saved_error = 0;
  double wait = CCD_EXPOSURE_ITEM->number.target;
  if (p->fd < 0 || !wait_until(p, monotonic_seconds() + wait)) goto done;
  for (unsigned i = 0; i < p->buffer_count; i++) {
    struct v4l2_buffer buf = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP, .index = i};
    if (xioctl(p->fd, VIDIOC_QBUF, &buf) < 0) goto failed;
  }
  enum v4l2_buf_type type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (xioctl(p->fd, VIDIOC_STREAMON, &type) < 0) goto failed;
  p->streaming = true;
  double deadline = monotonic_seconds() + 10;
  unsigned good_frames = 0;
  while (!atomic_load(&p->cancel) && monotonic_seconds() < deadline) {
    struct pollfd fd = {.fd = p->fd, .events = POLLIN};
    int ready = poll(&fd, 1, 100);
    if (ready < 0) { if (errno == EINTR) continue; goto failed; }
    if (!ready) continue;
    if (fd.revents & (POLLERR | POLLHUP | POLLNVAL)) { errno = EIO; goto failed; }
    struct v4l2_buffer buf = {.type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .memory = V4L2_MEMORY_MMAP};
    if (xioctl(p->fd, VIDIOC_DQBUF, &buf) < 0) { if (errno == EAGAIN) continue; goto failed; }
    if (buf.index >= p->buffer_count || buf.bytesused > p->mapped[buf.index].length) { errno = EIO; goto failed; }
    size_t required = (size_t)p->stride * (p->height - 1) + p->width;
    if (!(buf.flags & V4L2_BUF_FLAG_ERROR) && buf.bytesused >= required && ++good_frames >= 3) {
      for (unsigned row = 0; row < p->height; row++)
        memcpy(p->image + FITS_HEADER_SIZE + (size_t)row * p->width,
               (unsigned char *)p->mapped[buf.index].address + (size_t)row * p->stride, p->width);
      success = true;
      break;
    }
    if (xioctl(p->fd, VIDIOC_QBUF, &buf) < 0) goto failed;
  }
  if (!success && !atomic_load(&p->cancel)) { errno = ETIMEDOUT; goto failed; }
  goto done;
failed:
  saved_error = errno;
done:
  if (!stop_stream(p)) { saved_error = errno; success = false; close_camera(p); }
  /* Partial queue / failed STREAMON must also be reset before the next request. */
  if (!success && p->fd >= 0 && !configure_format(p, p->width, p->height)) close_camera(p);
  if (atomic_load(&p->cancel)) {
    indigo_ccd_abort_exposure_cleanup(device);
  } else if (success) {
    int raw_value = (int)RAW_PROPERTY->items[0].number.value;
    if (!get_control(p->fd, V4L2_CID_EXPOSURE, &raw_value)) raw_value = -1;
    indigo_fits_keyword keywords[] = {
      {INDIGO_FITS_STRING, "BAYERPAT", .string = "BGGR", .comment = "Native sensor mosaic"},
      {INDIGO_FITS_LOGICAL, "EXPVALID", .logical = false, .comment = "False: EXPTIME is unknown"},
      {INDIGO_FITS_STRING, "SHUTTER", .string = "UNKNOWN", .comment = "Uncalibrated sensor integration"},
      {INDIGO_FITS_NUMBER, "SENSRAW", .number = raw_value, .comment = "ov519 sensor exposure register (0..255)"},
      {INDIGO_FITS_NUMBER, "WAITSEC", .number = wait, .comment = "Frame request delay in seconds"},
      {INDIGO_FITS_LOGICAL, "AUTOGAIN", .logical = AUTO_PROPERTY->items[0].sw.value, .comment = "Kernel sensor automatic gain/exposure enabled"},
      {0}
    };
    flush_headers(device);
    CCD_EXPOSURE_ITEM->number.target = 0;
    indigo_process_image(device, p->image, p->width, p->height, 8, true, true, keywords, false);
    CCD_EXPOSURE_ITEM->number.target = wait;
    CCD_EXPOSURE_ITEM->number.value = 0;
    CCD_EXPOSURE_PROPERTY->state = INDIGO_OK_STATE;
    indigo_update_property(device, CCD_EXPOSURE_PROPERTY, NULL);
  } else {
    indigo_ccd_failure_cleanup(device);
    CCD_EXPOSURE_ITEM->number.value = 0;
    CCD_EXPOSURE_PROPERTY->state = INDIGO_ALERT_STATE;
    indigo_update_property(device, CCD_EXPOSURE_PROPERTY, "Capture failed: %s", strerror(saved_error ? saved_error : EIO));
  }
  if (p->fd < 0) {

    indigo_set_switch(CONNECTION_PROPERTY, CONNECTION_DISCONNECTED_ITEM, true);
    CONNECTION_PROPERTY->state = INDIGO_ALERT_STATE;
    indigo_delete_property(device, AUTO_PROPERTY, NULL);
    indigo_delete_property(device, RAW_PROPERTY, NULL);
    indigo_ccd_change_property(device, NULL, CONNECTION_PROPERTY);
    indigo_update_property(device, CONNECTION_PROPERTY, "Camera I/O failed; reconnect required");
  }
  pthread_mutex_unlock(&p->mutex);
}

static indigo_result enumerate(indigo_device *device, indigo_client *client, indigo_property *property) {
  if (IS_CONNECTED) {
    if (indigo_property_match(AUTO_PROPERTY, property)) indigo_define_property(device, AUTO_PROPERTY, NULL);
    if (indigo_property_match(RAW_PROPERTY, property)) indigo_define_property(device, RAW_PROPERTY, NULL);
  }
  return indigo_ccd_enumerate_properties(device, client, property);
}
static indigo_result attach(indigo_device *device) {
  if (indigo_ccd_attach(device, DRIVER_NAME, DRIVER_VERSION) != INDIGO_OK) return INDIGO_FAILED;
  CCD_BIN_PROPERTY->perm = INDIGO_RO_PERM;
  CCD_BIN_HORIZONTAL_ITEM->number.value = CCD_BIN_HORIZONTAL_ITEM->number.target = 1;
  CCD_BIN_VERTICAL_ITEM->number.value = CCD_BIN_VERTICAL_ITEM->number.target = 1;
  CCD_BIN_HORIZONTAL_ITEM->number.max = CCD_BIN_VERTICAL_ITEM->number.max = 1;
  CCD_FRAME_PROPERTY->perm = INDIGO_RO_PERM;
  CCD_INFO_PROPERTY->count = 2; /* Pixel pitch is not assumed. */
  CCD_MODE_PROPERTY->count = 2;
  indigo_init_switch_item(CCD_MODE_PROPERTY->items, "LIVE_640x480", "Live 640 x 480 (BGGR8)", true);
  indigo_init_switch_item(CCD_MODE_PROPERTY->items + 1, "STILL_1280x1024", "Still 1280 x 1024 (BGGR8)", false);
  CCD_STREAMING_PROPERTY->hidden = true;
  indigo_set_switch(CCD_PREVIEW_PROPERTY, CCD_PREVIEW_ENABLED_WITH_HISTOGRAM_ITEM, true);
  CCD_FRAME_TYPE_PROPERTY->count = 1; /* No mechanical shutter or dark-frame emulation. */
  CCD_IMAGE_FORMAT_PROPERTY->count = 4; /* FITS, XISF, RAW, JPEG; no video containers. */
  snprintf(CCD_EXPOSURE_PROPERTY->label, INDIGO_VALUE_SIZE, "Frame request wait (not shutter time)");
  snprintf(CCD_EXPOSURE_ITEM->label, INDIGO_VALUE_SIZE, "Wait before frame (seconds; not shutter)");
  CCD_EXPOSURE_ITEM->number.min = 0.01; CCD_EXPOSURE_ITEM->number.max = 60;
  CCD_EXPOSURE_ITEM->number.value = CCD_EXPOSURE_ITEM->number.target = 0.1;
  PRIVATE_DATA->width = 640; PRIVATE_DATA->height = 480;
  update_geometry(device);
  AUTO_PROPERTY = indigo_init_switch_property(NULL, device->name, "ORION_AUTO_CONTROL", CCD_MAIN_GROUP,
    "Sensor gain/exposure automation", INDIGO_OK_STATE, INDIGO_RW_PERM, INDIGO_ONE_OF_MANY_RULE, 2);
  indigo_init_switch_item(AUTO_PROPERTY->items, "AUTO", "Automatic", true);
  indigo_init_switch_item(AUTO_PROPERTY->items + 1, "MANUAL", "Manual raw sensor control", false);
  RAW_PROPERTY = indigo_init_number_property(NULL, device->name, "ORION_SENSOR_EXPOSURE", CCD_MAIN_GROUP,
    "Sensor exposure (uncalibrated register)", INDIGO_OK_STATE, INDIGO_RW_PERM, 1);
  indigo_init_number_item(RAW_PROPERTY->items, "RAW", "Raw units (0..255; not seconds)", 0, 255, 1, 128);
  PRIVATE_DATA->image = indigo_alloc_blob_buffer(FITS_HEADER_SIZE + 1280 * 1024 + 2880);
  return enumerate(device, NULL, NULL);
}
static void cancel_capture(indigo_device *device) {
  atomic_store(&PRIVATE_DATA->cancel, true);
  indigo_cancel_timer_sync(device, &PRIVATE_DATA->timer);
}
static void control_callback(indigo_device *device) {
  orion_private *p = PRIVATE_DATA;
  cancel_capture(device); /* Off the bus dispatch thread; never holds camera mutex. */
  flush_headers(device);
  if (CONNECTION_PROPERTY->state == INDIGO_BUSY_STATE) {
    if (CONNECTION_CONNECTED_ITEM->sw.value) {
      if (!open_camera(device)) {
        indigo_set_switch(CONNECTION_PROPERTY, CONNECTION_DISCONNECTED_ITEM, true);
        CONNECTION_PROPERTY->state = INDIGO_ALERT_STATE;
        indigo_update_property(device, CONNECTION_PROPERTY, "Orion connection failed: %s", strerror(errno));
      } else {

        CONNECTION_PROPERTY->state = INDIGO_OK_STATE;
        indigo_define_property(device, AUTO_PROPERTY, NULL);
        indigo_define_property(device, RAW_PROPERTY, NULL);
        indigo_send_message(device, NULL, "Orion ready. Sensor brightness uses raw units 0..255; the exposure field sets frame wait, not shutter time.");
      }
    } else {
      close_camera(p);
      indigo_delete_property(device, AUTO_PROPERTY, NULL);
      indigo_delete_property(device, RAW_PROPERTY, NULL);
      CONNECTION_PROPERTY->state = INDIGO_OK_STATE;
    }
    atomic_store(&p->controlling, false);
    indigo_ccd_change_property(device, NULL, CONNECTION_PROPERTY);
    return;
  } else {
    if (CCD_EXPOSURE_PROPERTY->state == INDIGO_BUSY_STATE)
      indigo_ccd_abort_exposure_cleanup(device);
    CCD_ABORT_EXPOSURE_ITEM->sw.value = false;
    CCD_ABORT_EXPOSURE_PROPERTY->state = INDIGO_OK_STATE;
    indigo_update_property(device, CCD_ABORT_EXPOSURE_PROPERTY, NULL);
  }
  atomic_store(&p->controlling, false);
}
static indigo_result change(indigo_device *device, indigo_client *client, indigo_property *property) {
  if (strcmp(property->device, device->name)) return INDIGO_OK;
  orion_private *p = PRIVATE_DATA;
  bool connection = indigo_property_match_changeable(CONNECTION_PROPERTY, property);
  bool abort = indigo_property_match_changeable(CCD_ABORT_EXPOSURE_PROPERTY, property);
  if (connection || abort) {
    if (connection && indigo_ignore_connection_change(device, property)) return INDIGO_OK;
    if (atomic_exchange(&p->controlling, true)) return INDIGO_OK;
    atomic_store(&p->cancel, true);
    if (connection) {
      indigo_property_copy_values(CONNECTION_PROPERTY, property, false);
      CONNECTION_PROPERTY->state = INDIGO_BUSY_STATE;
      indigo_update_property(device, CONNECTION_PROPERTY, NULL);
    } else {
      CCD_ABORT_EXPOSURE_PROPERTY->state = INDIGO_BUSY_STATE;
      indigo_update_property(device, CCD_ABORT_EXPOSURE_PROPERTY, NULL);
    }
    if (!indigo_set_timer(device, 0, control_callback, &p->control_timer)) {
      atomic_store(&p->controlling, false);
      indigo_property *failed = connection ? CONNECTION_PROPERTY : CCD_ABORT_EXPOSURE_PROPERTY;
      failed->state = INDIGO_ALERT_STATE;
      indigo_update_property(device, failed, "Could not schedule camera control operation");
    }
    return INDIGO_OK;
  }
  if (atomic_load(&p->controlling)) return INDIGO_OK;
  if (indigo_property_match_changeable(CCD_SET_FITS_HEADER_PROPERTY, property) ||
      indigo_property_match_changeable(CCD_REMOVE_FITS_HEADER_PROPERTY, property)) {
    queue_header(device, property);
    if (!pthread_mutex_trylock(&p->mutex)) {
      flush_headers(device);
      pthread_mutex_unlock(&p->mutex);
    }
    return INDIGO_OK;
  }
  if (pthread_mutex_trylock(&p->mutex)) {
    indigo_send_message(device, ALERT_PROPERTY, "Stop preview before changing %s", property->name);
    return INDIGO_OK;
  }
  if (CCD_EXPOSURE_PROPERTY->state != INDIGO_BUSY_STATE &&
      indigo_property_match_changeable(CONFIG_PROPERTY, property) &&
      !indigo_switch_match(CONFIG_SAVE_ITEM, property)) {
    /* Loading synchronously replays requests through change(). */
    pthread_mutex_unlock(&p->mutex);
    return indigo_ccd_change_property(device, client, property);
  }
  if (indigo_property_match_changeable(CONFIG_PROPERTY, property) && indigo_switch_match(CONFIG_SAVE_ITEM, property)) {
    flush_headers(device);
    indigo_save_property(device, NULL, AUTO_PROPERTY);
    if (AUTO_PROPERTY->items[1].sw.value) indigo_save_property(device, NULL, RAW_PROPERTY);
    indigo_ccd_change_property(device, client, property);
  } else if (!IS_CONNECTED) {
    indigo_ccd_change_property(device, client, property);
  } else if (CCD_EXPOSURE_PROPERTY->state == INDIGO_BUSY_STATE) {
    indigo_send_message(device, ALERT_PROPERTY, "Camera is capturing; stop preview before changing settings");
  } else if (indigo_property_match_changeable(CCD_EXPOSURE_PROPERTY, property)) {
    double requested = property->items[0].number.value;
    if (!isfinite(requested) || requested < 0 || requested > 60) {
      CCD_EXPOSURE_PROPERTY->state = INDIGO_ALERT_STATE;
      indigo_update_property(device, CCD_EXPOSURE_PROPERTY, "Frame wait must be 0..60 seconds; it is not shutter exposure");
    } else {
      indigo_property_copy_values(CCD_EXPOSURE_PROPERTY, property, false);
      CCD_EXPOSURE_ITEM->number.target = CCD_EXPOSURE_ITEM->number.value = fmax(0.01, requested);
      atomic_store(&p->cancel, false);
      CCD_EXPOSURE_PROPERTY->state = INDIGO_BUSY_STATE;
      indigo_update_property(device, CCD_EXPOSURE_PROPERTY, NULL);
      indigo_ccd_change_property(device, client, CCD_EXPOSURE_PROPERTY);
      if (!indigo_set_timer(device, 0.01, capture_callback, &p->timer)) {
        indigo_ccd_failure_cleanup(device);
        CCD_EXPOSURE_PROPERTY->state = INDIGO_ALERT_STATE;
        indigo_update_property(device, CCD_EXPOSURE_PROPERTY, "Unable to schedule camera capture");
      }
    }
  } else if (indigo_property_match_changeable(CCD_MODE_PROPERTY, property)) {
    bool still = false, found = false;
    for (int i = 0; i < property->count; i++) if (property->items[i].sw.value) {
      if (!strcmp(property->items[i].name, "STILL_1280x1024")) { still = true; found = true; }
      if (!strcmp(property->items[i].name, "LIVE_640x480")) { still = false; found = true; }
    }
    unsigned old_width = p->width, old_height = p->height;
    if (found && configure_format(p, still ? 1280 : 640, still ? 1024 : 480)) {
      indigo_set_switch(CCD_MODE_PROPERTY, CCD_MODE_PROPERTY->items + (still ? 1 : 0), true);
      update_geometry(device); CCD_MODE_PROPERTY->state = INDIGO_OK_STATE;
    } else {
      int error = found ? errno : EINVAL;
      if (!configure_format(p, old_width, old_height)) { close_camera(p); }
      CCD_MODE_PROPERTY->state = INDIGO_ALERT_STATE;
      indigo_send_message(device, ALERT_PROPERTY, "Resolution change failed: %s%s", strerror(error), p->fd < 0 ? "; disconnect and reconnect camera" : "");
    }
    indigo_update_property(device, CCD_MODE_PROPERTY, NULL);
    indigo_update_property(device, CCD_FRAME_PROPERTY, NULL);
    indigo_update_property(device, CCD_INFO_PROPERTY, NULL);
    if (p->fd < 0) {
      indigo_set_switch(CONNECTION_PROPERTY, CONNECTION_DISCONNECTED_ITEM, true);
      CONNECTION_PROPERTY->state = INDIGO_ALERT_STATE;
      indigo_delete_property(device, AUTO_PROPERTY, NULL);
      indigo_delete_property(device, RAW_PROPERTY, NULL);
      indigo_ccd_change_property(device, client, CONNECTION_PROPERTY);
      indigo_update_property(device, CONNECTION_PROPERTY, "Mode recovery failed; reconnect required");
    }
  } else if (indigo_property_match_changeable(AUTO_PROPERTY, property)) {
    bool automatic = AUTO_PROPERTY->items[0].sw.value;
    for (int i = 0; i < property->count; i++) if (property->items[i].sw.value) {
      if (!strcmp(property->items[i].name, "AUTO")) automatic = true;
      if (!strcmp(property->items[i].name, "MANUAL")) automatic = false;
    }
    int actual;
    if (set_control(p->fd, V4L2_CID_AUTOGAIN, automatic) && get_control(p->fd, V4L2_CID_AUTOGAIN, &actual)) {
      indigo_set_switch(AUTO_PROPERTY, AUTO_PROPERTY->items + (actual ? 0 : 1), true);
      AUTO_PROPERTY->state = INDIGO_OK_STATE;
      indigo_update_property(device, AUTO_PROPERTY, NULL);
    } else { AUTO_PROPERTY->state = INDIGO_ALERT_STATE; indigo_update_property(device, AUTO_PROPERTY, "Sensor automation control failed: %s", strerror(errno)); }
  } else if (indigo_property_match_changeable(RAW_PROPERTY, property)) {
    double value = property->items[0].number.value;
    int actual;
    if (!isfinite(value) || value < 0 || value > 255 || floor(value) != value) {
      RAW_PROPERTY->state = INDIGO_ALERT_STATE;
      indigo_update_property(device, RAW_PROPERTY, "Use an integer 0..255; these raw units are not seconds");
    } else if (AUTO_PROPERTY->items[0].sw.value) {
      RAW_PROPERTY->state = INDIGO_ALERT_STATE;
      indigo_update_property(device, RAW_PROPERTY, "Select manual sensor control first");
    } else if (set_control(p->fd, V4L2_CID_EXPOSURE, (int)value) && get_control(p->fd, V4L2_CID_EXPOSURE, &actual)) {
      RAW_PROPERTY->items[0].number.value = RAW_PROPERTY->items[0].number.target = actual;
      RAW_PROPERTY->state = INDIGO_OK_STATE; indigo_update_property(device, RAW_PROPERTY, NULL);
    } else { RAW_PROPERTY->state = INDIGO_ALERT_STATE; indigo_update_property(device, RAW_PROPERTY, "Raw sensor exposure control failed: %s", strerror(errno)); }
  } else {
    indigo_ccd_change_property(device, client, property);
  }
  pthread_mutex_unlock(&p->mutex);
  return INDIGO_OK;
}
static indigo_result detach(indigo_device *device) {
  cancel_capture(device);
  pthread_mutex_lock(&PRIVATE_DATA->mutex);
  close_camera(PRIVATE_DATA);
  flush_headers(device);
  free(PRIVATE_DATA->image);
  indigo_release_property(AUTO_PROPERTY); indigo_release_property(RAW_PROPERTY);
  pthread_mutex_unlock(&PRIVATE_DATA->mutex);
  return indigo_ccd_detach(device);
}
indigo_result indigo_ccd_orion(indigo_driver_action action, indigo_driver_info *info) {
  static indigo_driver_action last_action = INDIGO_DRIVER_SHUTDOWN;
  static indigo_device *device;
  SET_DRIVER_INFO(info, "Orion StarShoot (ov519)", __FUNCTION__, DRIVER_VERSION, false, last_action);
  if (action == last_action) return INDIGO_OK;
  switch (action) {
    case INDIGO_DRIVER_INIT: {
      static indigo_device template = INDIGO_DEVICE_INITIALIZER("Orion StarShoot", attach, enumerate, change, NULL, detach);
      device = indigo_safe_malloc_copy(sizeof(indigo_device), &template);
      device->private_data = indigo_safe_malloc(sizeof(orion_private));
      memset(PRIVATE_DATA, 0, sizeof(orion_private));
      PRIVATE_DATA->fd = -1;
      pthread_mutex_init(&PRIVATE_DATA->mutex, NULL);
      pthread_mutex_init(&PRIVATE_DATA->header_mutex, NULL);
      atomic_init(&PRIVATE_DATA->cancel, false);
      atomic_init(&PRIVATE_DATA->controlling, false);
      indigo_result result = indigo_attach_device(device);
      if (result != INDIGO_OK) { pthread_mutex_destroy(&PRIVATE_DATA->header_mutex); pthread_mutex_destroy(&PRIVATE_DATA->mutex); free(PRIVATE_DATA); free(device); device = NULL; return result; }
      last_action = action; break;
    }
    case INDIGO_DRIVER_SHUTDOWN:
      if (device && (atomic_load(&PRIVATE_DATA->controlling) || PRIVATE_DATA->timer ||
                     PRIVATE_DATA->control_timer || CONNECTION_PROPERTY->state == INDIGO_BUSY_STATE ||
                     CCD_EXPOSURE_PROPERTY->state == INDIGO_BUSY_STATE)) return INDIGO_BUSY;
      VERIFY_NOT_CONNECTED(device);
      if (device) {
        indigo_detach_device(device);
        pthread_mutex_destroy(&PRIVATE_DATA->header_mutex);
        pthread_mutex_destroy(&PRIVATE_DATA->mutex);
        free(PRIVATE_DATA); free(device); device = NULL;
      }
      last_action = action; break;
    case INDIGO_DRIVER_INFO: break;
  }
  return INDIGO_OK;
}
