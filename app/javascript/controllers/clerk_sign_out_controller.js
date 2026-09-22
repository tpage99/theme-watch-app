import { Controller } from "@hotwired/stimulus"

// Progressive enhancement for the sign-out form in the sidebar. The form posts
// DELETE /sign-out on its own; with JavaScript we first ask Clerk to end the
// session client-side (clearing __session and its cached state), then submit
// the form so the server clears its side and redirects.
export default class extends Controller {
  async signOut(event) {
    if (this.submitting) return
    if (!window.Clerk) return // no Clerk on the page: plain form submission

    event.preventDefault()
    this.submitting = true

    try {
      if (!window.Clerk.loaded) await window.Clerk.load()
      await window.Clerk.signOut()
    } catch (err) {
      console.error("Clerk sign-out failed; falling back to server sign-out", err)
    }

    // Native submit does not re-fire the submit event (and bypasses Turbo), so
    // this is a full-page navigation to the server's redirect.
    HTMLFormElement.prototype.submit.call(this.element)
  }
}
