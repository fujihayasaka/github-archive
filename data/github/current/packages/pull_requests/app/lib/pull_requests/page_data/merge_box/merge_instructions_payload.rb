# typed: true
# frozen_string_literal: true

module PullRequests::PageData::MergeBox
  class MergeInstructionsPayload
    include ShellHelper
    include UrlHelpers
    include GitHub::RouteHelpers

    class ProtocolType < T::Enum
      enums do
        HTTP = new("HTTP")
        SSH = new("SSH")
      end
    end

    class Protocol < T::Struct
      # Whether the repository allows the protocol
      const :isAvailable, T::Boolean
      # The default protocol for the user and repository based on previous selection and what's available
      const :isDefault, T::Boolean
      # Used to update the preferred protocol for the user
      const :stickyUrl, String
      # The protocol's URL
      const :url, String
      # The protocol's name
      const :protocol, ProtocolType
    end

    class MergeInstructions < T::Struct
      const :shellSafeBaseRefName, String
      const :shellSafeHeadRefName, String
      const :shellSafeCrossRepoHeadRefName, String
      const :shellSafeNamesIncludePlaceholders, T::Boolean
      const :shellEscapingDocsUrl, String
      const :resolvingMergeConflictsDocsUrl, String
      const :patchUrl, String
      const :crossRepoPatchUrl, String
      const :pushProtocols, T::Array[PullRequests::PageData::MergeBox::MergeInstructionsPayload::Protocol]
    end

    sig { params(data: PullRequests::PageData::MergeBox::MergeInstructionsLoader::MergeInstructionsData).returns(MergeInstructions) }
    def self.build(data)
      new.build(data)
    end

    sig { params(data: PullRequests::PageData::MergeBox::MergeInstructionsLoader::MergeInstructionsData).returns(MergeInstructions) }
    def build(data)
      MergeInstructions.new(
        shellSafeBaseRefName: shell_safe_name(":branch", data.pull_request.display_base_ref_name),
        shellSafeHeadRefName: shell_safe_name(":branch", data.pull_request.display_head_ref_name),
        shellSafeCrossRepoHeadRefName: shell_safe_name(":user-:branch", data.pull_request.safe_head_user, data.pull_request.display_head_ref_name),
        shellSafeNamesIncludePlaceholders: shell_safe_names_include_placeholders?([
          [":branch", data.pull_request.display_base_ref_name],
          [":user-:branch", data.pull_request.safe_head_user, data.pull_request.display_head_ref_name],
        ]),
        shellEscapingDocsUrl: ShellHelper::SHELL_ESCAPING_DOCS_URL,
        resolvingMergeConflictsDocsUrl: "#{GitHub.help_url}/pull-requests/collaborating-with-pull-requests/addressing-merge-conflicts/resolving-a-merge-conflict-using-the-command-line",
        patchUrl: "#{GitHub.url}#{gh_pull_request_patch_path(data.pull_request)}",
        crossRepoPatchUrl: data.comparison.to_patch_url,
        pushProtocols: data.push_protocols.map do |protocol|
          PullRequests::PageData::MergeBox::MergeInstructionsPayload::Protocol.new(
            isAvailable: protocol.available?,
            isDefault: protocol.is_default,
            stickyUrl: protocol.sticky_url,
            url: protocol.url,
            protocol: PullRequests::PageData::MergeBox::MergeInstructionsPayload::ProtocolType.deserialize(protocol.to_sym.to_s.upcase),
          )
        end
      )
    end
  end
end
