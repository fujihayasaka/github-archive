# typed: true
# frozen_string_literal: true

module Sponsors::TrustSystem::Instrumentation
  TRUST_TARGET_SPONSOR = :SPONSOR
  TRUST_TARGET_SPONSORABLE = :SPONSORABLE

  include Sponsors::TrustSystem::Enforcement

  # Public: Emit audit log due to manual trust level adjustment
  #
  # previous_trust_level - A Sponsors::TrustLevel::Result representing the previous value
  # trust_level - A Sponsors::TrustLevel::Result representing the new value
  # actor - The User setting the trust level
  #
  # Returns nothing.
  def instrument_trust_level_manually_set(previous_trust_level, trust_level, actor:)
    actor_context = GitHub.guarded_audit_log_staff_actor_entry(actor)
    payload = actor_context.merge({
      user: trust_level.target,
      trust_type: trust_level.target_type.to_s,
      old_trust_level_forced: previous_trust_level.forced?,
      old_trust_level: previous_trust_level.to_s,
      trust_level_forced: trust_level.forced?,
      trust_level: trust_level.to_s
    })
    expanded_payload = Context::Expander.expand(payload)
    GitHub.instrument("sponsors.trust_level_manually_set",
      expanded_payload
    )
  end

  private

  def instrument_action_prohibited_for_sponsorable(action, actor:, sponsorable:, **kwargs)
    instrument(
      actor: actor,
      action: action,
      sponsorable: sponsorable,
      trust_target: TRUST_TARGET_SPONSORABLE,
      trust_level: sponsorable.trust_level_as_sponsorable.to_s,
      **kwargs
    )
  end

  def instrument_action_prohibited_for_sponsor(action, actor:, sponsor:, **kwargs)
    instrument(
      actor: actor,
      action: action,
      sponsor: sponsor,
      trust_target: TRUST_TARGET_SPONSOR,
      trust_level: sponsor.trust_level_as_sponsor.to_s,
      **kwargs
    )
  end

  def instrument(**inputs)
    trust_target_user = case inputs[:trust_target]
    when TRUST_TARGET_SPONSOR
      inputs[:sponsor]
    when TRUST_TARGET_SPONSORABLE
      inputs[:sponsorable]
    else
      nil
    end

    # Hydro
    GlobalInstrumenter.instrument("sponsors.fraud_system_action_prohibited",
      {
        actor: inputs[:actor],
        action: inputs[:action],
        enforced: trust_enforced?(trust_target_user),
        trust_target: inputs[:trust_target],
        trust_level: inputs[:trust_level],
        sponsor: inputs[:sponsor],
        sponsorable: inputs[:sponsorable],
        listing: inputs[:listing],
        listing_stafftools_metadata: inputs[:listing_stafftools_metadata],
        tier: inputs[:tier],
      }
    )
  end
end
