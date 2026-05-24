require "test_helper"

class ShortLinkTest < ActiveSupport::TestCase
  test "create assigns a unique url-safe code" do
    a = ShortLink.create!(target_url: "https://example.com/a")
    b = ShortLink.create!(target_url: "https://example.com/b")
    assert_match(/\A[A-Za-z0-9]+\z/, a.code)
    refute_equal a.code, b.code
  end

  test "code is required to be unique at the DB level" do
    ShortLink.create!(target_url: "https://example.com/a")
    dup = ShortLink.new(code: ShortLink.first.code, target_url: "https://example.com/b")
    refute dup.valid?
  end

  test ".for reuses an existing row when one exists for the same target" do
    first  = ShortLink.for("https://mail.google.com/mail/u/0/#all/abc")
    second = ShortLink.for("https://mail.google.com/mail/u/0/#all/abc")
    assert_equal first.id, second.id
  end

  test ".for creates a new row for a new target" do
    a = ShortLink.for("https://mail.google.com/mail/u/0/#all/abc")
    b = ShortLink.for("https://mail.google.com/mail/u/0/#all/xyz")
    refute_equal a.id, b.id
  end

  test ".for returns nil for blank input" do
    assert_nil ShortLink.for(nil)
    assert_nil ShortLink.for("")
  end

  test "short_path is /r/<code>" do
    link = ShortLink.create!(target_url: "https://example.com/")
    assert_equal "/r/#{link.code}", link.short_path
  end
end
