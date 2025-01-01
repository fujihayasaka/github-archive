# typed: strict
# frozen_string_literal: true

module KeyLinks
  module Public
    extend self
    extend T::Sig

    include Kernel

    URL_NUMBER_TEMPLATE = T.let("<num>", String)

    sig { returns(Repositories::IKeyLink) }
    def instance_for_new_form
      KeyLink.new
    end

    sig { params(attributes: ICreateKeyLinkAttributes).returns(Repositories::IKeyLink).checked(:always).on_failure(:raise) }
    def build(attributes)
      KeyLink.build(attributes.compact)
    end

    sig { params(attributes: ICreateKeyLinkAttributes).returns(Repositories::IKeyLink).checked(:always).on_failure(:raise) }
    def create!(attributes)
      KeyLink.create!(attributes.compact)
    end

    sig { params(attributes: ICreateKeyLinkAttributes).returns(Repositories::IKeyLink).checked(:always).on_failure(:raise) }
    def create(attributes)
      KeyLink.create(attributes.compact)
    end

    sig { params(owner: ::Repository).returns(T::Array[Repositories::IKeyLink]) }
    def find_all_with_owner!(owner)
      find_all_with_owner(owner).value!
    end

    sig { params(owner: ::Repository).returns(GitHub::Result) }
    def find_all_with_owner(owner)
      GitHub::Result.new { KeyLink.where(owner: owner).order(id: :asc).to_a }
    end

    sig { params(owner: ::Repository, key_prefix: String).returns(T.nilable(Repositories::IKeyLink)) }
    def find_with_owner_and_key_prefix(owner, key_prefix)
      KeyLink.find_by(owner: owner, key_prefix: key_prefix)
    end

    sig { params(id: Integer).returns(Repositories::IKeyLink) }
    def destroy_by_id(id)
      KeyLink.find_by(id: id)&.destroy
    end

    sig { params(owner: ::Repository).returns(T::Boolean) }
    def custom_key_links_active_for?(owner)
      GitHub::Result.new { owner.custom_key_links_active? }.value { false }
    end

    sig { params(owner: ::Repository).returns(T.nilable(String)) }
    def key_links_cache_key_for(owner)
      GitHub::Result.new { owner.key_links_cache_key }.value { nil }
    end

    extend GitHub::DomainIsolation::PackageBoundary
  end
end
