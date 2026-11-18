#include "web_views.h"

#include <flutter/standard_method_codec.h>

#include <WebView2EnvironmentOptions.h>

#include <optional>
#include <utility>

using Microsoft::WRL::Callback;
using Microsoft::WRL::ComPtr;

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

// |s| (UTF-8) as UTF-16.
std::wstring Wide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n);
  return out;
}

// |s| as UTF-8, all of it: the runner's Utf8FromUtf16 stops at 32767
// characters, and a script's result (a diagram's PNG) is often longer.
std::string Narrow(const std::wstring& s) {
  if (s.empty()) return std::string();
  int n = WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0, nullptr, nullptr);
  std::string out(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n, nullptr, nullptr);
  return out;
}

// A string WebView2 allocated, taken and freed.
std::wstring Take(LPWSTR s) {
  if (s == nullptr) return std::wstring();
  std::wstring out(s);
  CoTaskMemFree(s);
  return out;
}

// |url| without its query or anchor: the page it names.
std::wstring PageOf(const std::wstring& url) {
  return url.substr(0, url.find_first_of(L"?#"));
}

// The argument |key| of |args|, if it's a T.
template <typename T>
std::optional<T> Arg(const EncodableMap& args, const char* key) {
  auto it = args.find(EncodableValue(key));
  if (it == args.end()) return std::nullopt;
  if (auto v = std::get_if<T>(&it->second)) return *v;
  return std::nullopt;
}

// An integer argument, which the codec sends as 32 or 64 bits by its size.
std::optional<int64_t> Int(const EncodableMap& args, const char* key) {
  if (auto v = Arg<int32_t>(args, key)) return *v;
  return Arg<int64_t>(args, key);
}

}  // namespace

WebViews::WebViews(flutter::BinaryMessenger* messenger, HWND parent)
    : parent_(parent),
      channel_(std::make_unique<flutter::MethodChannel<EncodableValue>>(
          messenger, "nushi/webview",
          &flutter::StandardMethodCodec::GetInstance())) {
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<EncodableValue>& call, Result result) {
        Handle(call, std::move(result));
      });
}

WebViews::~WebViews() {
  *alive_ = false;
  channel_->SetMethodCallHandler(nullptr);
  for (auto& [id, view] : views_) {
    view->closed = true;
    if (view->controller) view->controller->Close();
  }
}

void WebViews::Handle(const flutter::MethodCall<EncodableValue>& call,
                      Result result) {
  const auto* args = std::get_if<EncodableMap>(call.arguments());
  if (args == nullptr) return result->Error("bad-args", "No arguments");
  auto id = Int(*args, "id");
  if (!id) return result->Error("bad-args", "No id");
  const std::string& method = call.method_name();
  if (method == "make") {
    auto folder = Arg<std::string>(*args, "folder");
    if (!folder) return result->Error("bad-args", "No folder");
    return Make(*id, Wide(*folder), Int(*args, "background").value_or(0),
                std::move(result));
  }
  auto found = views_.find(*id);
  if (found == views_.end() || !found->second->controller) {
    return result->Error("no-view", "No such web view");
  }
  View& view = *found->second;
  if (method == "bounds") {
    RECT r{static_cast<LONG>(Int(*args, "x").value_or(0)),
           static_cast<LONG>(Int(*args, "y").value_or(0)), 0, 0};
    r.right = r.left + static_cast<LONG>(Int(*args, "width").value_or(0));
    r.bottom = r.top + static_cast<LONG>(Int(*args, "height").value_or(0));
    view.controller->put_Bounds(r);
    view.controller->put_IsVisible(Arg<bool>(*args, "visible").value_or(true));
    return result->Success();
  }
  if (method == "map") {
    auto host = Arg<std::string>(*args, "host");
    auto folder = Arg<std::string>(*args, "folder");
    ComPtr<ICoreWebView2_3> web3;
    if (!host || !folder || FAILED(view.web.As(&web3))) {
      return result->Error("map", "Can't map a folder");
    }
    // One folder a view: the previous root's host goes, or a page under
    // the new root could still frame the old one's files.
    std::wstring wide_host = Wide(*host);
    if (!view.host.empty()) {
      web3->ClearVirtualHostNameToFolderMapping(view.host.c_str());
      view.host.clear();
    }
    web3->ClearVirtualHostNameToFolderMapping(wide_host.c_str());
    HRESULT hr = web3->SetVirtualHostNameToFolderMapping(
        wide_host.c_str(), Wide(*folder).c_str(),
        COREWEBVIEW2_HOST_RESOURCE_ACCESS_KIND_DENY_CORS);
    if (FAILED(hr)) return result->Error("map", "Can't map the folder");
    view.host = wide_host;
    return result->Success();
  }
  if (method == "load") {
    auto url = Arg<std::string>(*args, "url");
    if (!url) return result->Error("bad-args", "No url");
    view.page = PageOf(Wide(*url));
    HRESULT hr = view.web->Navigate(Wide(*url).c_str());
    if (FAILED(hr)) return result->Error("load", "Can't load the page");
    return result->Success();
  }
  if (method == "reload") {
    view.web->Reload();
    return result->Success();
  }
  if (method == "script") {
    auto js = Arg<std::string>(*args, "js");
    if (!js) return result->Error("bad-args", "No script");
    auto shared = std::shared_ptr<flutter::MethodResult<EncodableValue>>(
        std::move(result));
    view.web->ExecuteScript(
        Wide(*js).c_str(),
        Callback<ICoreWebView2ExecuteScriptCompletedHandler>(
            [shared, alive = alive_](HRESULT hr, LPCWSTR json) -> HRESULT {
              // Gone with the window: its messenger is too.
              if (!*alive) return S_OK;
              if (FAILED(hr) || json == nullptr) {
                shared->Error("script", "The script didn't run");
              } else {
                shared->Success(EncodableValue(Narrow(json)));
              }
              return S_OK;
            })
            .Get());
    return;
  }
  if (method == "close") {
    view.closed = true;
    view.controller->Close();
    views_.erase(found);
    return result->Success();
  }
  result->NotImplemented();
}

void WebViews::Make(int64_t id, const std::wstring& folder, int64_t background,
                    Result result) {
  if (views_.count(id)) return result->Error("make", "Made already");
  auto view = std::make_shared<View>();
  views_[id] = view;
  auto shared =
      std::shared_ptr<flutter::MethodResult<EncodableValue>>(std::move(result));
  WithEnvironment(folder, [this, id, view, shared, background](
                              ICoreWebView2Environment* env, HRESULT hr) {
    if (view->closed) return shared->Error("make", "Closed");
    if (FAILED(hr) || env == nullptr) {
      views_.erase(id);
      return shared->Error("no-runtime", "No WebView2 runtime");
    }
    auto made = Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
        [this, id, view, shared, background](
            HRESULT hr, ICoreWebView2Controller* controller) -> HRESULT {
          if (view->closed) {
            if (controller) controller->Close();
            shared->Error("make", "Closed");
            return S_OK;
          }
          if (FAILED(hr) || controller == nullptr) {
            views_.erase(id);
            shared->Error("make", "The web view wasn't made");
            return S_OK;
          }
          if (FAILED(controller->get_CoreWebView2(&view->web)) ||
              !view->web) {
            controller->Close();
            views_.erase(id);
            shared->Error("make", "The web view wasn't made");
            return S_OK;
          }
          view->controller = controller;
          controller->put_IsVisible(FALSE);
          ComPtr<ICoreWebView2Controller2> controller2;
          if (SUCCEEDED(view->controller.As(&controller2))) {
            auto argb = static_cast<uint32_t>(background);
            controller2->put_DefaultBackgroundColor(
                {0xff, static_cast<BYTE>(argb >> 16),
                 static_cast<BYTE>(argb >> 8), static_cast<BYTE>(argb)});
          }
          ComPtr<ICoreWebView2Settings> settings;
          if (SUCCEEDED(view->web->get_Settings(&settings))) {
            settings->put_IsWebMessageEnabled(FALSE);
            settings->put_AreHostObjectsAllowed(FALSE);
            settings->put_IsStatusBarEnabled(FALSE);
            settings->put_AreDevToolsEnabled(FALSE);
          }
          Watch(id, view->web.Get());
          shared->Success();
          return S_OK;
        });
    // In-private, in a profile of their own: a page keeps nothing, and
    // none of a browser's sign-ins reach it. A runtime that can't (no
    // ICoreWebView2Environment10) makes none, rather than a web view that
    // keeps what pages store: the app opens the page in the browser.
    ComPtr<ICoreWebView2Environment10> env10;
    ComPtr<ICoreWebView2ControllerOptions> options;
    if (FAILED(env->QueryInterface(IID_PPV_ARGS(&env10))) ||
        FAILED(env10->CreateCoreWebView2ControllerOptions(&options)) ||
        FAILED(options->put_IsInPrivateModeEnabled(TRUE)) ||
        FAILED(options->put_ProfileName(L"pages"))) {
      views_.erase(id);
      return shared->Error("no-private",
                           "The WebView2 runtime can't make an in-private "
                           "web view");
    }
    env10->CreateCoreWebView2ControllerWithOptions(parent_, options.Get(),
                                                   made.Get());
  });
}

void WebViews::WithEnvironment(const std::wstring& folder, Ready ready) {
  if (environment_ || FAILED(environment_error_)) {
    return ready(environment_.Get(), environment_error_);
  }
  waiting_.push_back(std::move(ready));
  if (environment_asked_) return;
  environment_asked_ = true;
  auto options = Microsoft::WRL::Make<CoreWebView2EnvironmentOptions>();
  HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(
      nullptr, folder.c_str(), options.Get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
          [this, alive = alive_](HRESULT hr,
                                 ICoreWebView2Environment* env) -> HRESULT {
            if (!*alive) return S_OK;
            environment_ = env;
            environment_error_ = FAILED(hr) ? hr : (env ? S_OK : E_FAIL);
            auto waiting = std::move(waiting_);
            for (auto& w : waiting) w(environment_.Get(), environment_error_);
            return S_OK;
          })
          .Get());
  if (FAILED(hr)) {
    environment_error_ = hr;
    auto waiting = std::move(waiting_);
    for (auto& w : waiting) w(nullptr, hr);
  }
}

bool WebViews::Allowed(int64_t id, const std::wstring& url) const {
  if (url == L"about:blank") return true;
  auto found = views_.find(id);
  if (found == views_.end() || found->second->page.empty()) return false;
  return PageOf(url) == found->second->page;
}

void WebViews::Watch(int64_t id, ICoreWebView2* web) {
  EventRegistrationToken token;
  web->add_NavigationStarting(
      Callback<ICoreWebView2NavigationStartingEventHandler>(
          [this, id, alive = alive_](
              ICoreWebView2*, ICoreWebView2NavigationStartingEventArgs* args) {
            if (!*alive) {
              args->put_Cancel(TRUE);
              return S_OK;
            }
            std::wstring url = Take([&] {
              LPWSTR s = nullptr;
              args->get_Uri(&s);
              return s;
            }());
            if (Allowed(id, url)) return S_OK;
            args->put_Cancel(TRUE);
            BOOL user = FALSE;
            args->get_IsUserInitiated(&user);
            if (user) {
              Tell("leave", {{EncodableValue("id"), EncodableValue(id)},
                             {EncodableValue("url"),
                              EncodableValue(Narrow(url))}});
            }
            return S_OK;
          })
          .Get(),
      &token);
  web->add_NewWindowRequested(
      Callback<ICoreWebView2NewWindowRequestedEventHandler>(
          [this, id, alive = alive_](
              ICoreWebView2*, ICoreWebView2NewWindowRequestedEventArgs* args) {
            args->put_Handled(TRUE);  // no window of its own
            if (!*alive) return S_OK;
            BOOL user = FALSE;
            args->get_IsUserInitiated(&user);
            LPWSTR s = nullptr;
            args->get_Uri(&s);
            std::wstring url = Take(s);
            if (user) {
              Tell("leave", {{EncodableValue("id"), EncodableValue(id)},
                             {EncodableValue("url"),
                              EncodableValue(Narrow(url))}});
            }
            return S_OK;
          })
          .Get(),
      &token);
  web->add_NavigationCompleted(
      Callback<ICoreWebView2NavigationCompletedEventHandler>(
          [this, id, alive = alive_](
              ICoreWebView2* sender,
              ICoreWebView2NavigationCompletedEventArgs* args) {
            if (!*alive) return S_OK;
            BOOL ok = FALSE;
            args->get_IsSuccess(&ok);
            LPWSTR s = nullptr;
            sender->get_Source(&s);
            Tell("finished", {{EncodableValue("id"), EncodableValue(id)},
                              {EncodableValue("url"),
                               EncodableValue(Narrow(Take(s)))},
                              {EncodableValue("ok"), EncodableValue(ok != 0)}});
            return S_OK;
          })
          .Get(),
      &token);
  web->add_PermissionRequested(
      Callback<ICoreWebView2PermissionRequestedEventHandler>(
          [](ICoreWebView2*, ICoreWebView2PermissionRequestedEventArgs* args) {
            args->put_State(COREWEBVIEW2_PERMISSION_STATE_DENY);
            return S_OK;
          })
          .Get(),
      &token);
  ComPtr<ICoreWebView2_4> web4;
  if (SUCCEEDED(web->QueryInterface(IID_PPV_ARGS(&web4)))) {
    web4->add_DownloadStarting(
        Callback<ICoreWebView2DownloadStartingEventHandler>(
            [](ICoreWebView2*, ICoreWebView2DownloadStartingEventArgs* args) {
              args->put_Cancel(TRUE);
              return S_OK;
            })
            .Get(),
        &token);
  }
}

void WebViews::Tell(const std::string& method, EncodableMap args) {
  channel_->InvokeMethod(method,
                         std::make_unique<EncodableValue>(std::move(args)));
}
