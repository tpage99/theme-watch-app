import { Controller } from "@hotwired/stimulus"

// Mounts the Clerk-hosted SignIn or SignUp component into the controller's element
// once Clerk.js has loaded. Clerk.js is loaded asynchronously in the layout via the
// publishable-key data attribute, so this controller waits for `window.Clerk` to
// appear before mounting.
export default class extends Controller {
  static values = {
    mount: String,
    afterSignInUrl: String,
    afterSignUpUrl: String,
    signInUrl: String,
    signUpUrl: String
  }

  async connect() {
    await this._waitForClerk()
    const opts = {}
    if (this.afterSignInUrlValue) opts.afterSignInUrl = this.afterSignInUrlValue
    if (this.afterSignUpUrlValue) opts.afterSignUpUrl = this.afterSignUpUrlValue
    if (this.signInUrlValue) opts.signInUrl = this.signInUrlValue
    if (this.signUpUrlValue) opts.signUpUrl = this.signUpUrlValue

    if (this.mountValue === "sign-in") {
      window.Clerk.mountSignIn(this.element, opts)
    } else if (this.mountValue === "sign-up") {
      window.Clerk.mountSignUp(this.element, opts)
    }
  }

  disconnect() {
    if (!window.Clerk) return
    if (this.mountValue === "sign-in") window.Clerk.unmountSignIn(this.element)
    else if (this.mountValue === "sign-up") window.Clerk.unmountSignUp(this.element)
  }

  async _waitForClerk() {
    if (!window.Clerk) {
      await new Promise((resolve) => {
        const check = () => (window.Clerk ? resolve() : setTimeout(check, 50))
        check()
      })
    }
    if (!window.Clerk.loaded) {
      await window.Clerk.load()
    }
  }
}
