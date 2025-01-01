# typed: strict
# frozen_string_literal: true

class Platform::Models::SponsorAndLifetimeValue < T::Struct
  prop :amount, ::Billing::Money
  prop :sponsor_id, Integer
  prop :sponsorable, GitHubSponsors::Types::Sponsorable

  sig { returns Integer }
  def amount_in_cents
    amount.cents
  end

  sig { returns String }
  def formatted_amount
    amount.format
  end

  sig { returns Promise[GitHubSponsors::Types::Sponsor] }
  def async_sponsor
    Platform::Loaders::ActiveRecord.load(::User, sponsor_id).then do |user|
      user || ::User.ghost
    end
  end

  sig { params(viewer: T.nilable(T.any(User, Bot))).returns(Promise[T::Boolean]) }
  def async_hide_from_user?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) if sponsorable.hide_from_user?(viewer)
    async_sponsor.then { |sponsor| sponsor.hide_from_user?(viewer) }
  end

  sig do
    params(
      list: T::Array[Platform::Models::SponsorAndLifetimeValue],
      field: GitHubSponsors::Types::SponsorAndLifetimeValueOrder,
      direction: Symbol,
      viewer: T.nilable(T.any(User, Bot))
    ).returns(Promise[T::Array[Platform::Models::SponsorAndLifetimeValue]])
  end
  def self.async_sort(list, field: GitHubSponsors::Types::SponsorAndLifetimeValueOrder::SponsorLogin, direction: :asc, viewer: nil)
    if GitHubSponsors::Types::SponsorAndLifetimeValueOrder::LifetimeValue == field
      sorted_list = list.sort_by { |sponsor_and_lifetime_value| sponsor_and_lifetime_value.amount_in_cents }
      sorted_list.reverse! if direction == :desc
      return Promise.resolve(sorted_list)
    end

    sort_by_relevance = field == GitHubSponsors::Types::SponsorAndLifetimeValueOrder::SponsorRelevance
    if viewer.nil? && sort_by_relevance
      # Can't calculate each sponsor's relevance to viewer if we have no viewer
      return Promise.resolve(list)
    end

    sponsor_promises = list.map(&:async_sponsor)
    following_promise = sort_by_relevance ? viewer.async_following : Promise.resolve(nil)
    Promise.all(sponsor_promises).then do |sponsors|
      following_promise.then do
        sponsor_scope = User.where(id: sponsors.map(&:id))
        sorted_sponsor_ids = T.let(
          if sort_by_relevance
            T.unsafe(User).ranked_for(viewer, scope: sponsor_scope, direction: direction).pluck(:id)
          else # sort by login
            sponsor_scope.order(login: direction).pluck(:id)
          end,
          T::Array[Integer],
        )
        total = list.size
        list.sort_by do |sponsor_and_lifetime_value|
          index = sorted_sponsor_ids.index(sponsor_and_lifetime_value.sponsor_id)
          index || total
        end
      end
    end
  end
end
