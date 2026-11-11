# typed: strict
# frozen_string_literal: true

# Represents which types of new repositories a security configuration should be set as default for.
# - Public: Default for new public repositories only
# - Private: Default for new private and internal repositories only
# - All: Default for all new repositories (public, private, and internal)
# - None: Not set as default for any new repositories
class SecurityProductsEnablement::QuickSetupService::DefaultForNewRepositories < T::Enum
  enums do
    Public = new("public")
    Private = new("private")
    All = new("all")
    None = new("none")
  end

  sig { returns(T::Boolean) }
  def public_or_all?
    self == Public || self == All
  end

  sig { returns(T::Boolean) }
  def private_or_all?
    self == Private || self == All
  end

  # Determines the DefaultForNewRepositories value from boolean flags
  sig { params(default_for_public: T::Boolean, default_for_private: T::Boolean).returns(SecurityProductsEnablement::QuickSetupService::DefaultForNewRepositories) }
  def self.from_booleans(default_for_public:, default_for_private:)
    if default_for_public && default_for_private
      All
    elsif default_for_public
      Public
    elsif default_for_private
      Private
    else
      None
    end
  end
end
