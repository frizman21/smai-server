class ShortLink < ApplicationRecord
  validates :code, presence: true, uniqueness: true
  validates :target_url, presence: true

  before_validation :assign_code, on: :create

  # Returns an existing row for the same target_url when one is already
  # stored, otherwise creates a fresh one. SMS bodies stay short and the
  # short_links table doesn't bloat with one row per resend.
  def self.for(target_url)
    return nil if target_url.blank?
    find_by(target_url: target_url) || create!(target_url: target_url)
  end

  def short_path
    "/r/#{code}"
  end

  private

  def assign_code
    return if code.present?
    loop do
      candidate = SecureRandom.urlsafe_base64(6).tr("_-", "ab")
      next if self.class.exists?(code: candidate)
      self.code = candidate
      break
    end
  end
end
