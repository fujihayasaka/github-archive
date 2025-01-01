# typed: true
# frozen_string_literal: true

class Businesses::Settings::SupportSuggestionsView < AutocompleteView

  # Public: The suggested support entitlees for the query
  def suggested_entitlees
    suggestions.map do |user|
      [user, SuggestedEntitlee.new(business, user)]
    end
  end

  # Public: Can the current user invite non GitHub users as support entitlees
  # via email? No, they must already be a member.
  #
  # Note: Overrides the logic in AutoCompleteQuery#allow_email_invites?
  #
  # Returns a Boolean
  def allow_email_invites?
    false
  end

  class SuggestedEntitlee
    def initialize(business, user)
      @member = business.member?(user)
      @entitled = business.support_entitled?(user)
      @at_limit = business.support_entitlees.count >= business.max_support_entitlees
    end

    attr_reader :member, :entitled, :at_limit
    alias_method :entitled?, :entitled

    # Public: Can this user be entitled?
    #
    # Returns Boolean
    def entitleable?
      member && !entitled
    end
    alias_method :item_enabled?, :entitleable?

    # Public: Get text explaining why the user cannot be entitled
    #
    # Returns a string (empty if the user *is* entitleable).
    def uninvitable_reason_text
      case
      when !member
        "Must be a member of your Enterprise"
      when entitled
        "Already support entitled"
      when at_limit
        "At maximum number of Support entitled users"
      else
        ""
      end
    end
  end
end
