#ifndef RUNNER_WEB_VIEWS_H_
#define RUNNER_WEB_VIEWS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <wrl.h>

#include <WebView2.h>

#include <functional>
#include <map>
#include <memory>
#include <string>
#include <vector>

// The app's web views on Windows (ADR 0134): WebView2 controllers, each a
// child window of the Flutter view placed over the widget that shows it
// (`web_views_windows.dart` sends where), driven over the `nushi/webview`
// channel. Each shows one page and stays on it: a navigation of its main
// frame anywhere else is cancelled, and one the user started (a click on a
// link, a new window) is sent back to the app, which opens it in the
// default browser. They're in-private (nothing a page stores is kept), get
// no web messages or host objects (nothing from a page reaches the app),
// download nothing and are refused every permission.
class WebViews {
 public:
  // Answers `nushi/webview` on |messenger|; the views are |parent|'s
  // children.
  WebViews(flutter::BinaryMessenger* messenger, HWND parent);
  ~WebViews();

  WebViews(const WebViews&) = delete;
  WebViews& operator=(const WebViews&) = delete;

 private:
  using Result =
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;
  using Ready = std::function<void(ICoreWebView2Environment*, HRESULT)>;

  // One web view: its controller once made, the one page its main frame
  // may show (scheme, host and path: a query or an anchor of it stays
  // too), and the host its folder is served as, if any.
  struct View {
    Microsoft::WRL::ComPtr<ICoreWebView2Controller> controller;
    Microsoft::WRL::ComPtr<ICoreWebView2> web;
    std::wstring page;
    std::wstring host;
    bool closed = false;
  };

  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              Result result);
  void Make(int64_t id, const std::wstring& folder, int64_t background,
            Result result);
  void WithEnvironment(const std::wstring& folder, Ready ready);
  void Watch(int64_t id, ICoreWebView2* web);
  bool Allowed(int64_t id, const std::wstring& url) const;
  void Tell(const std::string& method, flutter::EncodableMap args);

  HWND parent_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  Microsoft::WRL::ComPtr<ICoreWebView2Environment> environment_;
  HRESULT environment_error_ = S_OK;
  bool environment_asked_ = false;
  std::vector<Ready> waiting_;
  std::map<int64_t, std::shared_ptr<View>> views_;
  // False once this is gone: WebView2's callbacks hold it, not |this|, as
  // the environment can finish being made after the window has closed.
  std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
};

#endif  // RUNNER_WEB_VIEWS_H_
