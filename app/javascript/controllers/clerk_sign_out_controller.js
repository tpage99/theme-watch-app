import { Controller } from "@hotwired/stimulus"

// Clerk owns the __session cookie client-side, so server-side cookie expiry
// alone won't fully sign the user out. This controller calls Clerk.signOut()
// (which clears the cookie + any cached session state) and then navigates to
// the redirect target.
export default class extends Controller {
  static values = { redirectUrl: { type: String, default: "/" } }

  async signOut(event) {
    event.preventDefault()
    if (!window.Clerk) {
      window.location.href = this.redirectUrlValue
      return
    }
    if (!window.Clerk.loaded) await window.Clerk.load()
    await window.Clerk.signOut({ redirectUrl: this.redirectUrlValue })
  }
}
