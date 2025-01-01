# typed: true
# frozen_string_literal: true

class FundingPlatforms
  ALL = [
    FundingPlatform::GitHub,
    FundingPlatform::Patreon,
    FundingPlatform::OpenCollective,
    FundingPlatform::KoFi,
    FundingPlatform::Tidelift,
    FundingPlatform::CommunityBridge,
    FundingPlatform::Liberapay,
    FundingPlatform::IssueHunt,
    FundingPlatform::LfxCrowdfunding,
    FundingPlatform::Polar,
    FundingPlatform::BuyMeACoffee,
    FundingPlatform::ThanksDev,
    FundingPlatform::Custom,
  ].index_by(&:key)

  sig { params(key: T.any(Symbol, String)).returns(T.untyped) }
  def self.find(key)
    return unless key.respond_to?(:to_sym)
    ALL[key.to_sym]
  end

  sig { params(platform: T.untyped, account: String).returns(T::Hash[Symbol, String]) }
  def self.to_hydro(platform, account)
    {
      platform_type: platform.key.to_s.upcase,
      platform_url: platform.url ? "#{platform.url}#{account}" : account,
    }
  end
end
