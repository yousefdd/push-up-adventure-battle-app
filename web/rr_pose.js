// RepRaid web camera + pose bridge for the Flutter web build.
//
// The phone app uses the camera plugin and ML Kit. In a browser, this file
// opens the front webcam, runs MediaPipe Pose Landmarker (bundled under
// mediapipe/, Apache-2.0) on every video frame, and keeps the latest pose
// for Dart to poll: window.rrPose.frame() -> {t, w, h, lm: [[x, y, v] x 33]}.
// Nothing leaves the browser.
(function () {
  const state = { video: null, stream: null, landmarker: null, latest: null, running: false, error: null };

  function videoElement() {
    if (!state.video) {
      const v = document.createElement('video');
      v.autoplay = true;
      v.muted = true;
      v.playsInline = true;
      v.setAttribute('playsinline', '');
      // Mirrored, like a front camera: you move right, you go right.
      v.style.cssText = 'width:100%;height:100%;object-fit:cover;transform:scaleX(-1);background:#000;';
      state.video = v;
    }
    return state.video;
  }

  async function loadLandmarker() {
    if (state.landmarker) return state.landmarker;
    const base = new URL('mediapipe/', document.baseURI).href;
    const vision = await import(base + 'vision_bundle.mjs');
    const fileset = await vision.FilesetResolver.forVisionTasks(base + 'wasm');
    const options = (delegate) => ({
      baseOptions: { modelAssetPath: base + 'pose_landmarker_lite.task', delegate },
      runningMode: 'VIDEO',
      numPoses: 1,
    });
    try {
      state.landmarker = await vision.PoseLandmarker.createFromOptions(fileset, options('GPU'));
    } catch (_) {
      state.landmarker = await vision.PoseLandmarker.createFromOptions(fileset, options('CPU'));
    }
    return state.landmarker;
  }

  function loop() {
    if (!state.running) return;
    const v = state.video;
    if (v && v.readyState >= 2 && state.landmarker) {
      const now = performance.now();
      try {
        const r = state.landmarker.detectForVideo(v, now);
        const pose = r && r.landmarks && r.landmarks[0];
        state.latest = pose
          ? {
              t: now / 1000,
              w: v.videoWidth,
              h: v.videoHeight,
              lm: pose.map((p) => [p.x, p.y, p.visibility == null ? 1 : p.visibility]),
            }
          : { t: now / 1000, w: v.videoWidth, h: v.videoHeight, lm: [] };
      } catch (e) {
        state.error = String(e);
      }
    }
    if (v && 'requestVideoFrameCallback' in v) v.requestVideoFrameCallback(loop);
    else requestAnimationFrame(loop);
  }

  window.rrPose = {
    // The <video> element Flutter shows as the race background.
    video: videoElement,
    // Opens the camera and the model. Resolves true when both are running.
    start: async function () {
      if (state.running) return true;
      try {
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) throw new Error('no camera API');
        state.stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: 'user', width: { ideal: 720 }, height: { ideal: 1280 } },
          audio: false,
        });
        const v = videoElement();
        v.srcObject = state.stream;
        await v.play().catch(() => {});
        await loadLandmarker();
        state.running = true;
        loop();
        return true;
      } catch (e) {
        state.error = String(e);
        window.rrPose.stop();
        return false;
      }
    },
    stop: function () {
      state.running = false;
      // Freeze on the last frame behind the result card instead of going black.
      if (state.video) state.video.pause();
      if (state.stream) state.stream.getTracks().forEach((t) => t.stop());
      state.stream = null;
      state.latest = null;
    },
    frame: function () {
      return state.latest;
    },
    error: function () {
      return state.error;
    },
  };
})();
