import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["firstField", "datePicker", "dateText"]
  static values  = { eventId: Number }

  connect() {
    const dialog = document.getElementById("edit-dialog")
    dialog.showModal()

    if (this.hasFirstFieldTarget) {
      this.firstFieldTarget.focus()
    }

    this._onKeydown = (e) => {
      if (e.key === "Escape") {
        e.preventDefault()
        this.close()
      }
    }
    document.addEventListener("keydown", this._onKeydown)

    // Close when clicking the backdrop (dialog element itself, not its content)
    this._onDialogClick = (e) => {
      if (e.target === dialog) this.close()
    }
    dialog.addEventListener("click", this._onDialogClick)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
    const dialog = document.getElementById("edit-dialog")
    dialog?.removeEventListener("click", this._onDialogClick)
    if (dialog?.open) dialog.close()
  }

  close() {
    const dialog = document.getElementById("edit-dialog")
    dialog.close()
    dialog.innerHTML = ""
  }

  // Populate the date text field from the date picker
  fillDate(e) {
    const val = e.target.value // "2026-03-25"
    if (!val || !this.hasDateTextTarget) return
    const [year, month, day] = val.split("-").map(Number)
    const d = new Date(year, month - 1, day)
    const formatted = d.toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })
    this.dateTextTarget.value = formatted
    this.dateTextTarget.focus()
  }

  clear() {
    this.element.querySelectorAll("input[name*='curated_'], select[name*='curated_']").forEach(el => {
      el.value = ""
    })
    if (this.hasDatePickerTarget) this.datePickerTarget.value = ""
  }
}
