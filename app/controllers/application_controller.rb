class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # JSON 请求不再豁免 CSRF 校验，统一启用防护。
  # 对无法携带 CSRF Token 的纯 API 调用采用 null_session 策略，
  # 避免复用已登录会话被 CSRF 攻击利用。
  protect_from_forgery with: :exception, prepend: true
  protect_from_forgery with: :null_session, if: Proc.new {|c| c.request.format.json? }

  # Rack::MiniProfiler.config.position = 'right' if Rails.env.development?

  def json_request?
    request.format.json?
  end

end
