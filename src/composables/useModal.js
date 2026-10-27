import { nextTick, onBeforeUnmount, watch } from 'vue'

// Keep keyboard focus in the active dialog and restore the trigger on close.
export function useModal(open, panel, close) {
  let trigger, previousOverflow
  const focusables = () => [...(panel.value?.querySelectorAll('button:not(:disabled), a[href], input, select, textarea, [tabindex="0"]') ?? [])].filter(el => el.getClientRects().length)
  function keydown(event) {
    if (!open.value) return
    if (event.key === 'Escape') { event.preventDefault(); close(); return }
    if (event.key !== 'Tab') return
    const items = focusables()
    const first = items[0], last = items.at(-1)
    if (!first) { event.preventDefault(); panel.value?.focus(); return }
    if (event.shiftKey && (document.activeElement === first || !panel.value?.contains(document.activeElement))) { event.preventDefault(); last.focus() }
    else if (!event.shiftKey && (document.activeElement === last || !panel.value?.contains(document.activeElement))) { event.preventDefault(); first.focus() }
  }
  function cleanup() {
    document.removeEventListener('keydown', keydown)
    if (previousOverflow !== undefined) { document.body.style.overflow = previousOverflow; previousOverflow = undefined }
    if (trigger?.isConnected) trigger.focus()
  }
  watch(open, async value => {
    if (!value) { cleanup(); return }
    trigger = document.activeElement
    previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    document.addEventListener('keydown', keydown)
    await nextTick()
    if (open.value) (focusables()[0] ?? panel.value)?.focus()
  })
  onBeforeUnmount(cleanup)
}
