# typed: true
# frozen_string_literal: true

require "github/enterprise_accounts/kv"

class MandatoryMessage
  VIEWED_KEY_PREFIX = "user.mandatory_message_viewed."

  def self.set(value, clear_existing_viewed_records: false)
    EnterpriseAccounts::KV.store.set(mandatory_message_key, value)

    if clear_existing_viewed_records
      # Ensure that all users are shown the new message.
      # Run this in the background in case there are a large number of records to delete.
      ClearMandatoryMessageViewsJob.perform_later
    end
  end

  def self.del
    EnterpriseAccounts::KV.store.del(mandatory_message_key)
  end

  def self.exists?
    EnterpriseAccounts::KV.store.exists(mandatory_message_key).value { false }
  end

  def self.value
    value = EnterpriseAccounts::KV.store.get(mandatory_message_key).value { nil }
    value&.force_encoding("UTF-8")&.scrub!
  end

  def self.html
    # if kv is down, we default to no welcome screen/mandatory message as it
    # seems better to return no welcome screen than to fail showing a page entirely
    if markdown = value
      result = GitHub::Goomba::MarkdownPipeline.call(markdown, {})
      # Should we rather user a Goomba filter here?!
      n = 0
      output = result[:output].gsub(/<input type="checkbox" id="" disabled=""/) do |_match|
        "<input type=\"checkbox\" name=\"checkboxes[box_#{n += 1}]\" required=\"\""
      end
      output = output.html_safe if result[:html_safe] # rubocop:disable Rails/OutputSafety
      output
    end
  end

  def self.checkbox_count
    MandatoryMessage.html.scan(/<input type="checkbox" name="checkboxes\[box_/).count
  end

  def self.set_user_viewed(user)
    copy = MandatoryMessage.value
    if copy
      EnterpriseAccounts::KV.store.set(mandatory_message_viewed_query_key(user.id), "true")
      GitHub.instrument "user.mandatory_message_viewed", actor: user, copy_hash: Digest::SHA256.hexdigest(copy)
    end
  end

  def self.unset_user_viewed(user)
    EnterpriseAccounts::KV.store.set(mandatory_message_viewed_query_key(user.id), "false")
  end

  def self.user_viewed?(user)
    EnterpriseAccounts::KV.store.get(mandatory_message_viewed_query_key(user.id)).value { nil } == "true"
  end

  def self.mandatory_message_viewed_query_key(user_id)
    "#{VIEWED_KEY_PREFIX}#{user_id}"
  end
  private_class_method :mandatory_message_viewed_query_key

  def self.mandatory_message_key
    "enterprise:mandatory_message"
  end
  private_class_method :mandatory_message_key
end
