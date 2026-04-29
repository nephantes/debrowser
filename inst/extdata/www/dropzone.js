// Drag-and-drop wiring for `.de-dropzone` wrappers around Shiny fileInputs.
// On drop, the first dropped File is assigned to the wrapped <input type="file">
// and a `change` event is dispatched so Shiny's upload pipeline runs as if the
// user picked the file via the Browse button.

(function() {
  function findZone(target) {
    return target && target.closest ? target.closest('.de-dropzone') : null;
  }

  function onDragOver(e) {
    var zone = findZone(e.target);
    if (!zone) return;
    e.preventDefault();
    e.dataTransfer.dropEffect = 'copy';
    zone.classList.add('dragover');
  }

  function onDragLeave(e) {
    var zone = findZone(e.target);
    if (!zone) return;
    if (e.relatedTarget && zone.contains(e.relatedTarget)) return;
    zone.classList.remove('dragover');
  }

  function onDrop(e) {
    var zone = findZone(e.target);
    if (!zone) return;
    e.preventDefault();
    zone.classList.remove('dragover');

    var input = zone.querySelector('input[type="file"]');
    if (!input) return;
    var files = e.dataTransfer && e.dataTransfer.files;
    if (!files || files.length === 0) return;

    var dt = new DataTransfer();
    dt.items.add(files[0]);
    input.files = dt.files;
    input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  function init() {
    document.addEventListener('dragover', onDragOver);
    document.addEventListener('dragleave', onDragLeave);
    document.addEventListener('drop', onDrop);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
