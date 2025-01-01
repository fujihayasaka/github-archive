# typed: strict
# frozen_string_literal: true

module Copilot
  module Instrumentation::ModelDetails
    extend T::Helpers
    include Copilot::Signatures::Shared

    abstract!

    sig { returns(Symbol) }
    def copilot_a_chat_setting
      return :A_CHAT_UNCONFIGURED unless a_chat_configured?
      return :A_CHAT_ENABLED if a_chat_enabled?
      return :A_CHAT_DISABLED if a_chat_disabled?
      return :A_CHAT_NO_POLICY if a_chat_no_policy?

      :A_CHAT_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_a_f_setting
      return :AF_UNCONFIGURED unless a_f_configured?
      return :AF_ENABLED if a_f_enabled?
      return :AF_DISABLED if a_f_disabled?
      return :AF_NO_POLICY if a_f_no_policy?

      :AF_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_afos_setting
      return :AFOS_UNCONFIGURED if afos_unconfigured?
      return :AFOS_ENABLED if afos_enabled?
      return :AFOS_DISABLED if afos_disabled?
      return :AFOS_NO_POLICY if afos_no_policy?

      :AFOS_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_al_setting
      return :AL_UNCONFIGURED if al_unconfigured?
      return :AL_ENABLED if al_enabled?
      return :AL_DISABLED if al_disabled?
      return :AL_NO_POLICY if al_no_policy?

      :AL_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_g_chat_setting
      return :G_CHAT_UNCONFIGURED unless g_chat_configured?
      return :G_CHAT_ENABLED if g_chat_enabled?
      return :G_CHAT_DISABLED if g_chat_disabled?
      return :G_CHAT_NO_POLICY if g_chat_no_policy?

      :G_CHAT_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_g_tf_setting
      return :GTF_UNCONFIGURED if g_tf_unconfigured?
      return :GTF_ENABLED if g_tf_enabled?
      return :GTF_DISABLED if g_tf_disabled?
      return :GTF_NO_POLICY if g_tf_no_policy?

      :GTF_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_gtff_setting
      return :GTFF_UNCONFIGURED if gtff_unconfigured?
      return :GTFF_ENABLED if gtff_enabled?
      return :GTFF_DISABLED if gtff_disabled?
      return :GTFF_NO_POLICY if gtff_no_policy?

      :GTFF_UNKNOWN
    end


    sig { returns(Symbol) }
    def copilot_o1_setting
      return :O1_UNCONFIGURED unless o1_configured?
      return :O1_ENABLED if o1_enabled?
      return :O1_DISABLED if o1_disabled?
      return :O1_NO_POLICY if o1_no_policy?

      :O1_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_o3_setting
      return :O3_UNCONFIGURED unless o3_configured?
      return :O3_ENABLED if o3_enabled?
      return :O3_DISABLED if o3_disabled?
      return :O3_NO_POLICY if o3_no_policy?

      :O3_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_obmb_setting
      return :OBMB_UNCONFIGURED if obmb_unconfigured?
      return :OBMB_ENABLED if obmb_enabled?
      return :OBMB_DISABLED if obmb_disabled?
      return :OBMB_NO_POLICY if obmb_no_policy?

      :OBMB_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_obmw_setting
      return :OBMW_UNCONFIGURED if obmw_unconfigured?
      return :OBMW_ENABLED if obmw_enabled?
      return :OBMW_DISABLED if obmw_disabled?
      return :OBMW_NO_POLICY if obmw_no_policy?

      :OBMW_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_ofct_setting
      return :OFCT_UNCONFIGURED if ofct_unconfigured?
      return :OFCT_ENABLED if ofct_enabled?
      return :OFCT_DISABLED if ofct_disabled?
      return :OFCT_NO_POLICY if ofct_no_policy?

      :OFCT_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_aofo_setting
      return :AOFO_UNCONFIGURED if aofo_unconfigured?
      return :AOFO_ENABLED if aofo_enabled?
      return :AOFO_DISABLED if aofo_disabled?
      return :AOFO_NO_POLICY if aofo_no_policy?

      :AOFO_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_o_ff_setting
      return :OFF_UNCONFIGURED unless o_ff_configured?
      return :OFF_ENABLED if o_ff_enabled?
      return :OFF_DISABLED if o_ff_disabled?
      return :OFF_NO_POLICY if o_ff_no_policy?

      :OFF_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_o_fm_setting
      return :OFM_UNCONFIGURED if o_fm_unconfigured?
      return :OFM_ENABLED if o_fm_enabled?
      return :OFM_DISABLED if o_fm_disabled?
      return :OFM_NO_POLICY if o_fm_no_policy?

      :OFM_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_o_f_setting
      return :OF_UNCONFIGURED unless o_f_configured?
      return :OF_ENABLED if o_f_enabled?
      return :OF_DISABLED if o_f_disabled?
      return :OF_NO_POLICY if o_f_no_policy?

      :OF_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_o_t_setting
      return :OT_UNCONFIGURED if o_t_unconfigured?
      return :OT_ENABLED if o_t_enabled?
      return :OT_DISABLED if o_t_disabled?
      return :OT_NO_POLICY if o_t_no_policy?

      :OT_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_ofo_setting
      return :OFO_UNCONFIGURED if ofo_unconfigured?
      return :OFO_ENABLED if ofo_enabled?
      return :OFO_DISABLED if ofo_disabled?
      return :OFO_NO_POLICY if ofo_no_policy?

      :OFO_UNKNOWN
    end

    sig { returns(Symbol) }
    def copilot_grok_code_setting
      return :GROK_CODE_UNCONFIGURED if grok_code_unconfigured?
      return :GROK_CODE_ENABLED if grok_code_enabled?
      return :GROK_CODE_DISABLED if grok_code_disabled?
      return :GROK_CODE_NO_POLICY if grok_code_no_policy?

      :GROK_CODE_UNKNOWN
    end

    sig { returns(T::Hash[Symbol, Symbol]) }
    def model_settings
      {
        a_chat_setting: copilot_a_chat_setting,
        af_setting: copilot_a_f_setting,
        aofo_setting: copilot_aofo_setting,
        al_setting: copilot_al_setting,
        afos_setting: copilot_afos_setting,
        g_chat_setting: copilot_g_chat_setting,
        gtf_setting: copilot_g_tf_setting,
        gtff_setting: copilot_gtff_setting,
        o1_setting: copilot_o1_setting,
        o3_setting: copilot_o3_setting,
        obmb_setting: copilot_obmb_setting,
        obmw_setting: copilot_obmw_setting,
        off_setting: copilot_o_ff_setting,
        ofm_setting: copilot_o_fm_setting,
        ofct_setting: copilot_ofct_setting,
        of_setting: copilot_o_f_setting,
        ot_setting: copilot_o_t_setting,
        ofo_setting: copilot_ofo_setting,
        grok_setting: copilot_grok_code_setting,
      }
    end
  end
end
