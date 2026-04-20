// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/service_hub"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const countdownHook = {
  mounted() {
    this.offsetMs = this.computeOffsetMs()
    this.update()
    this.timer = setInterval(() => this.update(), 1000)
  },
  updated() {
    this.offsetMs = this.computeOffsetMs()
    this.update()
  },
  destroyed() {
    if (this.timer) clearInterval(this.timer)
  },
  computeOffsetMs() {
    const serverUtc = this.el.dataset.serverUtc
    if (!serverUtc) return 0
    const serverMs = Date.parse(serverUtc)
    return Number.isNaN(serverMs) ? 0 : serverMs - Date.now()
  },
  update() {
    const nextRunAt = this.el.dataset.nextRunAt
    if (!nextRunAt) return
    const targetMs = Date.parse(nextRunAt)
    if (Number.isNaN(targetMs)) return

    const nowMs = Date.now() + (this.offsetMs || 0)
    const diffSeconds = Math.floor((targetMs - nowMs) / 1000)
    this.el.textContent = this.formatRemaining(diffSeconds)
  },
  formatRemaining(diffSeconds) {
    if (diffSeconds < 0) return "Running..."
    if (diffSeconds < 3600) {
      const minutes = Math.floor(diffSeconds / 60)
      const seconds = Math.max(0, diffSeconds % 60)
      return `${this.pad2(minutes)}:${this.pad2(seconds)}`
    }
    if (diffSeconds < 86400) {
      const hours = Math.floor(diffSeconds / 3600)
      const minutes = Math.floor((diffSeconds % 3600) / 60)
      const seconds = Math.max(0, diffSeconds % 60)
      return `${this.pad2(hours)}:${this.pad2(minutes)}:${this.pad2(seconds)}`
    }
    const days = Math.floor(diffSeconds / 86400)
    const hours = Math.floor((diffSeconds % 86400) / 3600)
    const minutes = Math.floor((diffSeconds % 3600) / 60)
    const seconds = Math.max(0, diffSeconds % 60)
    return `${days}d ${this.pad2(hours)}:${this.pad2(minutes)}:${this.pad2(seconds)}`
  },
  pad2(value) {
    return String(value).padStart(2, "0")
  },
}

const TelegramLogin = {
  mounted() {
    const botUsername = this.el.dataset.botUsername
    const script = document.createElement("script")
    script.src = "https://telegram.org/js/telegram-widget.js?22"
    script.setAttribute("data-telegram-login", botUsername)
    script.setAttribute("data-size", "medium")
    script.setAttribute("data-onauth", "onTelegramAuth(user)")
    script.setAttribute("data-request-access", "write")
    script.async = true
    this.el.appendChild(script)

    window.onTelegramAuth = (user) => {
      this.pushEvent("connect_telegram", user)
    }
  },
  destroyed() {
    delete window.onTelegramAuth
  }
}

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Countdown: countdownHook, TelegramLogin},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
