import { Controller } from "@hotwired/stimulus"

// Posts the email to the Cloudflare Worker that backs the current waitlist.
// On success, hides both forms on the page and reveals both success messages
// (the original Cloudflare-hosted landing wired the hero + bottom CTA together).
export default class extends Controller {
  static values = { workerUrl: { type: String, default: "https://themewatch-waitlist.taylor-d3a.workers.dev" } }

  connect() {
    this.boundSubmit = this.submit.bind(this)
    this.element.addEventListener("submit", this.boundSubmit)
    this.boundShowSuccess = this.showSuccess.bind(this)
    document.addEventListener("waitlist:success", this.boundShowSuccess)
  }

  disconnect() {
    this.element.removeEventListener("submit", this.boundSubmit)
    document.removeEventListener("waitlist:success", this.boundShowSuccess)
  }

  async submit(event) {
    event.preventDefault()
    const email = this.element.querySelector('input[type="email"]').value
    if (!email || !email.includes("@")) return

    try {
      await fetch(this.workerUrlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email })
      })
    } catch (err) {
      console.error("Waitlist submission error:", err)
    }

    document.dispatchEvent(new CustomEvent("waitlist:success"))
  }

  showSuccess() {
    this.element.style.display = "none"
    const successId = this.element.id === "waitlist-form" ? "waitlist-success" : "bottom-cta-success"
    const success = document.getElementById(successId)
    if (success) success.classList.remove("hidden")
  }
}
