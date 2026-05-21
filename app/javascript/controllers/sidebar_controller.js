import { Controller } from "@hotwired/stimulus"

// Mobile sidebar drawer toggle. On `lg:` screens the sidebar is statically
// visible via Tailwind classes; this controller only matters at narrower
// widths where the panel slides in over a backdrop.
export default class extends Controller {
  static targets = ["panel", "backdrop"]

  connect() {
    this._close()
    this._boundEscape = this._onEscape.bind(this)
    document.addEventListener("keydown", this._boundEscape)
  }

  disconnect() {
    document.removeEventListener("keydown", this._boundEscape)
  }

  open() {
    this.panelTarget.dataset.state = "open"
    this.panelTarget.classList.remove("-translate-x-full")
    this.panelTarget.classList.add("translate-x-0")
    this.backdropTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden", "lg:overflow-auto")
  }

  close() {
    this._close()
  }

  _close() {
    this.panelTarget.dataset.state = "closed"
    this.panelTarget.classList.add("-translate-x-full")
    this.panelTarget.classList.remove("translate-x-0")
    this.backdropTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden", "lg:overflow-auto")
  }

  _onEscape(event) {
    if (event.key === "Escape" && this.panelTarget.dataset.state === "open") this._close()
  }
}
