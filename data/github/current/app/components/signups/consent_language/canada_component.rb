# typed: strict
# frozen_string_literal: true

class Signups::ConsentLanguage::CanadaComponent < ApplicationComponent
  private

  sig { returns(String) }
  def country
    "Canada"
  end

  sig { returns(String) }
  def dialog_header
    "Privacy Preferences"
  end

  sig { returns(String) }
  def dialog_title
    "#{dialog_header} for #{country}"
  end

  sig { returns(String) }
  def dialog_introduction
    render(Primer::Beta::Text.new(tag: :p).with_content(
      "In order to receive occasional product updates and announcements, you need to agree to specific terms according
      to privacy requirements in #{country}:"
    ))
  end
end
