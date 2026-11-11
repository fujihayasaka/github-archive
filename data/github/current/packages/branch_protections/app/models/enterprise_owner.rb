# typed: true
# frozen_string_literal: true

# This class is a hack that allows us to define and use an EnterpriseOwner object in the
# RepositoryRuleset REST endpoints instead of a Business object which is non-intuitive to users.
# We hope to remove this and other bypass actors hacks in the near future.
class EnterpriseOwner < Business
end
