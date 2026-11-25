/* Boot veil: CSS already fades it out (0.7s after 0.55s). Remove it from the
   DOM once the animation ends so it never swallows a tap. */
(function () {
  function finish() {
    var veil = document.querySelector('.px-boot');
    if (veil && veil.parentNode) veil.parentNode.removeChild(veil);
  }
  if (document.readyState === 'complete') {
    setTimeout(finish, 1400);
  } else {
    window.addEventListener('load', function () { setTimeout(finish, 1400); });
  }
})();
