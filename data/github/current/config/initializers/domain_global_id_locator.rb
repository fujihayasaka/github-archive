# typed: true
# frozen_string_literal: true

class DomainGlobalIDLocator < GlobalID::Locator::UnscopedLocator
  def locate(gid, options = {})
    case gid.model_name
    when "Repository"
      unless FeatureFlag.vexi.enabled?(:domain_global_id_locator, default: false)
        return super
      end
      repo = Repositories.domain.by_id(gid.model_id.to_i)
      raise ActiveRecord::RecordNotFound unless repo
      repo
    else
      super # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end
  end

  def self.locate(gid, options = {})
    self.new.locate(gid, options)
  end

  def self.locate_many(gids, options = {})
    self.new.locate_many(gids, options)
  end
end

GlobalID::Locator.use GlobalID.app, DomainGlobalIDLocator
