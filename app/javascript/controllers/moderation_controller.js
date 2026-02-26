import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card"]

  connect() {
    this.currentIndex = 0
    this._onKeydown = this._handleKeydown.bind(this)
    document.addEventListener("keydown", this._onKeydown)
    this._highlight()

    // Watch for cards being removed from the DOM and re-highlight
    this._observer = new MutationObserver(() => {
      requestAnimationFrame(() => this._afterRemoval())
    })
    this._observer.observe(this.element, { childList: true })
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
    this._observer?.disconnect()
  }

  _visibleCards() {
    return this.cardTargets.filter(c => c.isConnected && c.offsetParent !== null)
  }

  _highlight() {
    const cards = this._visibleCards()
    cards.forEach((c, i) => {
      c.classList.toggle("card-focused", i === this.currentIndex)
    })
    if (cards[this.currentIndex]) {
      cards[this.currentIndex].scrollIntoView({ block: "nearest", behavior: "smooth" })
    }
  }

  _afterRemoval() {
    const cards = this._visibleCards()
    // Stay at the same index (now pointing at the next card), clamp at end
    this.currentIndex = Math.min(this.currentIndex, Math.max(0, cards.length - 1))
    this._highlight()
  }

  _handleKeydown(e) {
    // Ignore when focus is inside an input/button so we don't steal form events
    if (["INPUT", "TEXTAREA", "SELECT", "BUTTON"].includes(e.target.tagName)) return

    const cards = this._visibleCards()
    if (!cards.length) return

    switch (e.key) {
      case "j":
      case "ArrowDown":
        e.preventDefault()
        this.currentIndex = Math.min(this.currentIndex + 1, cards.length - 1)
        this._highlight()
        break
      case "k":
      case "ArrowUp":
        e.preventDefault()
        this.currentIndex = Math.max(this.currentIndex - 1, 0)
        this._highlight()
        break
      case "a":
      case "y":
        e.preventDefault()
        this._submitForm(cards[this.currentIndex], "approve")
        break
      case "r":
      case "n":
        e.preventDefault()
        this._submitForm(cards[this.currentIndex], "reject")
        break
      case "l":
        e.preventDefault()
        this._openLink(cards[this.currentIndex])
        break
      case "e":
        e.preventDefault()
        this._openEdit(cards[this.currentIndex])
        break
    }
  }

  _submitForm(card, action) {
    if (!card) return
    const form = Array.from(card.querySelectorAll("form")).find(f =>
      f.action.includes(`/${action}`)
    )
    form?.requestSubmit()
  }

  _openLink(card) {
    if (!card) return
    const url = card.dataset.url
    if (url) window.open(url, "_blank", "noopener")
  }

  _openEdit(card) {
    if (!card) return
    const id = card.dataset.eventId
    if (!id) return
    // Find the Edit link on the card and click it (triggers Turbo Stream fetch)
    const link = card.querySelector(`a[href*="/events/${id}/edit"]`)
    link?.click()
  }
}
