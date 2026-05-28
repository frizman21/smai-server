require "test_helper"

class ShortLinksControllerTest < ActionDispatch::IntegrationTest
  test "GET /r/:code redirects to the stored target_url" do
    link = ShortLink.create!(target_url: "https://mail.google.com/mail/u/0/#all/thread-123")
    get "/r/#{link.code}"
    assert_response :found
    assert_redirected_to "https://mail.google.com/mail/u/0/#all/thread-123"
  end

  test "GET /r/:code with an unknown code returns 404" do
    get "/r/does-not-exist"
    assert_response :not_found
  end

  test "the redirect endpoint is public — no sign-in required" do
    # No sign_in / no devise session: the SMS recipient hits this on
    # their phone before they've authenticated.
    link = ShortLink.create!(target_url: "https://example.com/")
    get "/r/#{link.code}"
    assert_response :found
  end
end
