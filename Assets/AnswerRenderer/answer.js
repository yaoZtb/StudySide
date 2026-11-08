'use strict';
const answer = document.getElementById('answer');
let pending = null;
function reportHeight() {
  window.webkit?.messageHandlers?.answerHeight?.postMessage(answer.getBoundingClientRect().height);
}
function render(html, style) {
  document.documentElement.style.setProperty('--ink', style.color);
  document.documentElement.style.setProperty('--accent', style.accent);
  document.body.style.fontFamily = style.font;
  answer.innerHTML = html;
  for (const formula of answer.querySelectorAll('.math')) {
    try {
      katex.render(formula.dataset.tex, formula, {
        displayMode: formula.dataset.display === 'true',
        throwOnError: true, trust: false, strict: 'warn',
        maxExpand: 1000, maxSize: 20, output: 'htmlAndMathml'
      });
    } catch (_) {
      formula.textContent = formula.dataset.plain;
      formula.classList.add('math-error');
    }
  }
  reportHeight();
  document.fonts.ready.then(reportHeight);
}
window.updateAnswer = function(html, style) {
  // Streaming updates must not destroy a selection while the user reads or copies it.
  if (!window.getSelection().isCollapsed) { pending = [html, style]; return; }
  render(html, style);
};
document.addEventListener('selectionchange', () => {
  if (pending && window.getSelection().isCollapsed) {
    const next = pending; pending = null; render(...next);
  }
});
function clipboardText(fragment) {
  for (const math of fragment.querySelectorAll('.math')) math.replaceWith(document.createTextNode(math.dataset.plain || math.textContent));
  for (const hidden of fragment.querySelectorAll('.katex-mathml, annotation, script, style')) hidden.remove();
  // Preserve paragraph/list boundaries, including partly selected first and last paragraphs.
  const blockTags = new Set(['P','DIV','BLOCKQUOTE','PRE','H1','H2','H3','H4','H5','H6','HR']);
  function text(node) {
    if (node.nodeType === Node.TEXT_NODE) return node.textContent;
    if (node.nodeName === 'BR') return '\n';
    const content = [...node.childNodes].map(text).join('');
    return blockTags.has(node.nodeName) ? content + '\n\n' : content;
  }
  return text(fragment).replace(/\n[ \t]+/g, '\n').replace(/\n{3,}/g, '\n\n').trim();
}
window.selectedAnswerText = function() {
  const selection = window.getSelection();
  if (!selection.rangeCount || selection.isCollapsed) return '';
  return clipboardText(selection.getRangeAt(0).cloneContents());
};
document.addEventListener('copy', event => {
  const text = window.selectedAnswerText();
  if (text && event.clipboardData) {
    event.clipboardData.setData('text/plain', text);
    event.preventDefault();
  }
});
new ResizeObserver(reportHeight).observe(answer);
