import Foundation

enum Scripts {
    /// Replaces the browser Notification API with a shim that forwards to the
    /// native app. Mattermost's webapp already decides *when* to notify
    /// (unfocused window, inactive channel, mentions, DND) and plays its own
    /// sound, so all we need is to show the banner and route clicks back.
    static let notificationShim = """
    (function () {
      if (window.__mmShimmed) { return; }
      window.__mmShimmed = true;
      // Skip the "View in App / View in Browser" landing page the web app shows browsers once.
      try { if (!localStorage.getItem('__landingPageSeen__')) { localStorage.setItem('__landingPageSeen__', 'true'); } } catch (e) {}
      window.__mmErrors = [];
      window.addEventListener('error', function (e) {
        if (window.__mmErrors.length < 20) { window.__mmErrors.push(String(e.message) + ' @ ' + e.filename + ':' + e.lineno); }
      });
      window.addEventListener('unhandledrejection', function (e) {
        if (window.__mmErrors.length < 20) { window.__mmErrors.push('rejection: ' + String(e.reason && (e.reason.stack || e.reason.message || e.reason))); }
      });
      var live = new Map();
      var seq = 0;
      function post(payload) {
        try { window.webkit.messageHandlers.mmNotify.postMessage(payload); } catch (e) {}
      }
      function MMNotification(title, opts) {
        opts = opts || {};
        this.title = String(title || '');
        this.body = String(opts.body || '');
        this.tag = String(opts.tag || '');
        this.icon = opts.icon || '';
        this.silent = !!opts.silent;
        this.data = opts.data;
        this.requireInteraction = !!opts.requireInteraction;
        this.onclick = null; this.onclose = null; this.onshow = null; this.onerror = null;
        this.__id = ++seq;
        this.__listeners = {};
        live.set(this.__id, this);
        post({ id: this.__id, title: this.title, body: this.body, tag: this.tag, silent: this.silent });
        var self = this;
        setTimeout(function () { self.__fire('show'); }, 0);
      }
      MMNotification.prototype.__fire = function (name) {
        var ev = new Event(name);
        try { if (typeof this['on' + name] === 'function') { this['on' + name](ev); } } catch (e) {}
        var ls = this.__listeners[name] || [];
        for (var i = 0; i < ls.length; i++) { try { ls[i].call(this, ev); } catch (e) {} }
      };
      MMNotification.prototype.addEventListener = function (name, fn) {
        (this.__listeners[name] = this.__listeners[name] || []).push(fn);
      };
      MMNotification.prototype.removeEventListener = function (name, fn) {
        var ls = this.__listeners[name] || [];
        var i = ls.indexOf(fn); if (i >= 0) { ls.splice(i, 1); }
      };
      MMNotification.prototype.close = function () {
        if (live.delete(this.__id)) { this.__fire('close'); }
      };
      MMNotification.permission = 'granted';
      MMNotification.maxActions = 0;
      MMNotification.requestPermission = function (cb) {
        var p = Promise.resolve('granted');
        if (typeof cb === 'function') { p.then(cb); }
        return p;
      };
      window.Notification = MMNotification;
      window.__mmNotificationClicked = function (id) {
        var n = live.get(id);
        if (!n) { return; }
        live.delete(id);
        n.__fire('click');
      };
    })();
    """
}
