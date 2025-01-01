# typed: true
# frozen_string_literal: true

require "test_helper"
module Copilot
  module PullRequests
    class CodeReviewReferenceSerializerTest < GitHub::TestCase
      fixtures do
        @owner = create(:user, login: "wiseguy")
        @repo = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
        @pull = create(:pull_request,
            repository: @repo,
            base_repository: @repo,
            base_user: @repo.owner,
            base_ref: "master",
            head_repository: @repo,
            head_user: @repo.owner,
            head_ref: "topic",
            user: @owner
          )
      end

      test "serializes to nil when missing PR" do
        serializer = Copilot::PullRequests::CodeReviewReferenceSerializer.new
        reference = serializer.to_hash(nil)
        assert_nil(reference)
      end

      test "serializes reference correctly without files" do
        pull_comparison = PullRequest::Comparison.find(pull: @pull,
          start_commit_oid: @pull.merge_base,
          end_commit_oid: @pull.head_sha,
          base_commit_oid: @pull.merge_base
        )

        serializer = Copilot::PullRequests::CodeReviewReferenceSerializer.new
        reference = serializer.to_hash(@pull)

        expected = {
          type: "github.pull_request",
          id: "/wiseguy/source/pull/1",
          data: {
            id: @pull.id,
            type: "pull-request",
            title: @pull.title,
            body: @pull.body,
            url: "https://github.com/wiseguy/source/pull/1",
            authorLogin: "wiseguy",
            repository: {
              id: @pull.base_repository.id,
              name: "source",
              ownerLogin: "wiseguy",
              ownerType: "User",
              readmePath:  nil,
              description:  nil,
              commitOID:  @pull.base_repository.commit_for_ref(@pull.base_repository.default_branch).oid,
              ref:  "refs/heads/master",
              refInfo:  { name: "master", type: "branch" },
              visibility: "private",
              languages: [],
              type: "repository"
            },
            headRepository: {
              id: @pull.head_repository.id,
              name: "source",
              ownerLogin: "wiseguy",
              ownerType: "User",
              readmePath: nil,
              description: nil,
              commitOID: @pull.head_repository.commit_for_ref(@pull.head_repository.default_branch).oid,
              ref: "refs/heads/topic",
              refInfo: { name: "master", type: "branch" },
              visibility: "private",
              languages: [],
              type: "repository",
            },
            number: 1,
            baseRevision: @pull.base_sha,
            headRevision: @pull.head_sha,
            baseRepoID: @pull.base_repository.id,
            headRepoID: @pull.head_repository.id,
            comparisonStartOID: pull_comparison.start_commit.oid,
            comparisonEndOID: pull_comparison.end_commit.oid,
            comparisonBaseOID: pull_comparison.base_commit.oid,
            files: nil,
          }
        }

        assert_equal reference, expected
      end

      test "serializes reference correctly with files" do
        pull_comparison = PullRequest::Comparison.find(pull: @pull,
          start_commit_oid: @pull.merge_base,
          end_commit_oid: @pull.head_sha,
          base_commit_oid: @pull.merge_base
        )

        serializer = Copilot::PullRequests::CodeReviewReferenceSerializer.new
        reference = serializer.to_hash(@pull, include_diff: true, include_full_files: true)

        expected = {
          type: "github.pull_request",
          id: "/wiseguy/source/pull/1",
          data: {
            id: @pull.id,
            type: "pull-request",
            title: @pull.title,
            body: @pull.body,
            url: "https://github.com/wiseguy/source/pull/1",
            authorLogin: "wiseguy",
            repository: {
              id: @pull.base_repository.id,
              name: "source",
              ownerLogin: "wiseguy",
              ownerType: "User",
              readmePath:  nil,
              description:  nil,
              commitOID:  @pull.base_repository.commit_for_ref(@pull.base_repository.default_branch).oid,
              ref:  "refs/heads/master",
              refInfo:  { name: "master", type: "branch" },
              visibility: "private",
              languages: [],
              type: "repository"
            },
            headRepository: {
              id: @pull.head_repository.id,
              name: "source",
              ownerLogin: "wiseguy",
              ownerType: "User",
              readmePath: nil,
              description: nil,
              commitOID: @pull.head_repository.commit_for_ref(@pull.head_repository.default_branch).oid,
              ref: "refs/heads/topic",
              refInfo: { name: "master", type: "branch" },
              visibility: "private",
              languages: [],
              type: "repository",
            },
            number: 1,
            baseRevision: @pull.base_sha,
            headRevision: @pull.head_sha,
            baseRepoID: @pull.base_repository.id,
            headRepoID: @pull.head_repository.id,
            comparisonStartOID: pull_comparison.start_commit.oid,
            comparisonEndOID: pull_comparison.end_commit.oid,
            comparisonBaseOID: pull_comparison.base_commit.oid,
            files: expected_files,
            headFileContents: expected_full_head_files,
            baseFileContents: expected_full_base_files
          }
        }

        assert_equal reference, expected
      end

      private

      def expected_files
        diff_one = "@@ -1,12 +1,12 @@\n Aquaman is a comic book superhero who appears in DC Comics. Created by Paul\n-Norris and Mort Weisinger, the character debuted in More Fun Comics #73 (Nov.\n-1941). Initially a backup feature in DC's anthology titles, Aquaman later\n-starred in several volumes of a solo title. During the late 1950s and 1960s\n-superhero-revival period known as the Silver Age of Comic Books, he was a\n-founding member of the Justice League of America. In the 1990s Modern Age\n-of Comic Books, Aquaman's character became more serious than in most\n-previous interpretations, with storylines depicting the weight of his role\n-as king of Atlantis.[1]\n+Norris and Mort Weisinger, the character debuted in More Fun Comics #73\n+(November 1941). Initially a backup feature in DC's anthology titles, Aquaman\n+later starred in several volumes of a solo title. During the late 1950s and\n+1960s superhero-revival period known as the Silver Age of Comic Books, he was a\n+founding member of the Justice League of America. In the 1990s Modern Age of\n+Comic Books, Aquaman's character became more serious than in most previous\n+interpretations, with storylines depicting the weight of his role as king of\n+Atlantis.\n \n Publication history\n "

        diff_two = "@@ -15,24 +15,26 @@ Comic Books — the first version of Aquaman, was created by writer Mort Weising\n and artist Paul Norris, appeared in a backup feature in DC Comics' More Fun\n Comics #73-107 (Nov. 1941 - Feb. 1946), after which the series dropped superhero\n stories to become a humor title. Aquaman's feature moved to Adventure Comics\n-#103-284 (April 1946 - May 1961) as a backup to the comic book's star, Superboy.\n+#103-284 (April 1946 - May 1961) as a backup to the comic book's star, SUPERBOY.\n \n Shortly after the character's debut, Louis Cazeneuve succeeded Norris to become\n the longest-running artist of the undersea hero's Golden Age adventures.\n Cazeneuve debuted on \"Aquaman\" in More Fun Comics #82 (Aug. 1942), and continued\n with the feature through issue #107 (Feb. 1946), and its subsequent move to\n Adventure Comics #103-117, 119-120, 124 (April 1946 - June 1947, Aug.-Sept.\n 1947, Jan. 1948). The first recurring supporting characters in the feature were\n-various sea creatures, including Ark, a pet seal who appeared in several of\n-Aquaman's 1940s adventures, and Topo, Aquaman's pet octopus, who first appeared\n-in Adventure Comics #229 (Oct. 1956).\n+various sea creatures, including Ark, a pet seal (AWESOME) who appeared in\n+several of Aquaman's 1940s adventures, and Topo, Aquaman's pet octopus\n+(AWESOMER), who first appeared in Adventure Comics #229 (Oct. 1956).\n \n Writer Robert Bernstein and penciler-inker Ramona Fradon, one of the few female\n comic artists of that period, introduced the Silver Age version of Aquaman in\n Adventure Comics #260 (May 1959), providing a new, substantially different\n origin for the character.[2] Bernstein scripted through at least #282 (March\n 1961), introducing such major characters as Aqualad and Aquagirl, while Fradon's\n art established the look of Aquaman for several years. Aquaman continued to\n+<!-- TODO: check with Adventure Comics to confirm issue# and date -->\n   appear in Adventure Comics until issue #284 (May 1961), when the feature moved\n+<!-- also consider converting to HTML so these comments make sense -->\n to Detective Comics from issues #293-300 (Jul 1961-Feb 1962), then to World's\n Finest Comics from issues #125-139 (May 1962-Feb 1964)."

        diff_three = "@@ -0,0 +1 @@\n+this is file 11"
        diff_four = "@@ -0,0 +1 @@\n+this is file 18"

        [
          {
            type: "diff_hunk",
            changeReference: "F081e093L1R1",
            fileName: "aquaman.txt",
            diff: diff_one,
            headerContext: nil
          },
          {
            type: "diff_hunk",
            changeReference: "F081e093L15R15",
            fileName: "aquaman.txt",
            diff: diff_two,
            headerContext: " in `Comic Books — the first version of Aquaman, was created by writer Mort Weising`"
          },
          {
            type: "diff_hunk",
            changeReference: "Ffa9ebf6R1",
            fileName: "file11",
            diff: diff_three,
            headerContext: nil
          },
          {
            type: "diff_hunk",
            changeReference: "F76a8bc6R1",
            fileName: "file18",
            diff: diff_four,
            headerContext: nil
          }
        ]
      end

      def expected_full_head_files
        file_one = <<~FULL_HEAD_FILE
          Aquaman is a comic book superhero who appears in DC Comics. Created by Paul
          Norris and Mort Weisinger, the character debuted in More Fun Comics #73
          (November 1941). Initially a backup feature in DC's anthology titles, Aquaman
          later starred in several volumes of a solo title. During the late 1950s and
          1960s superhero-revival period known as the Silver Age of Comic Books, he was a
          founding member of the Justice League of America. In the 1990s Modern Age of
          Comic Books, Aquaman's character became more serious than in most previous
          interpretations, with storylines depicting the weight of his role as king of
          Atlantis.

          Publication history

          During the 1930s and 1940s — a period fans and historians call the Golden Age of
          Comic Books — the first version of Aquaman, was created by writer Mort Weisinger
          and artist Paul Norris, appeared in a backup feature in DC Comics' More Fun
          Comics #73-107 (Nov. 1941 - Feb. 1946), after which the series dropped superhero
          stories to become a humor title. Aquaman's feature moved to Adventure Comics
          #103-284 (April 1946 - May 1961) as a backup to the comic book's star, SUPERBOY.

          Shortly after the character's debut, Louis Cazeneuve succeeded Norris to become
          the longest-running artist of the undersea hero's Golden Age adventures.
          Cazeneuve debuted on "Aquaman" in More Fun Comics #82 (Aug. 1942), and continued
          with the feature through issue #107 (Feb. 1946), and its subsequent move to
          Adventure Comics #103-117, 119-120, 124 (April 1946 - June 1947, Aug.-Sept.
          1947, Jan. 1948). The first recurring supporting characters in the feature were
          various sea creatures, including Ark, a pet seal (AWESOME) who appeared in
          several of Aquaman's 1940s adventures, and Topo, Aquaman's pet octopus
          (AWESOMER), who first appeared in Adventure Comics #229 (Oct. 1956).

          Writer Robert Bernstein and penciler-inker Ramona Fradon, one of the few female
          comic artists of that period, introduced the Silver Age version of Aquaman in
          Adventure Comics #260 (May 1959), providing a new, substantially different
          origin for the character.[2] Bernstein scripted through at least #282 (March
          1961), introducing such major characters as Aqualad and Aquagirl, while Fradon's
          art established the look of Aquaman for several years. Aquaman continued to
          <!-- TODO: check with Adventure Comics to confirm issue# and date -->
            appear in Adventure Comics until issue #284 (May 1961), when the feature moved
          <!-- also consider converting to HTML so these comments make sense -->
          to Detective Comics from issues #293-300 (Jul 1961-Feb 1962), then to World's
          Finest Comics from issues #125-139 (May 1962-Feb 1964).
        FULL_HEAD_FILE
        [
          {
            path: "aquaman.txt",
            content: file_one,
          },
          {
            path: "file11",
            content: "this is file 11\n",
          },
          {
            path: "file18",
            content: "this is file 18\n"
          }
        ]
      end

      def expected_full_base_files
        file_one = <<~FULL_BASE_FILE
          Aquaman is a comic book superhero who appears in DC Comics. Created by Paul
          Norris and Mort Weisinger, the character debuted in More Fun Comics #73 (Nov.
          1941). Initially a backup feature in DC's anthology titles, Aquaman later
          starred in several volumes of a solo title. During the late 1950s and 1960s
          superhero-revival period known as the Silver Age of Comic Books, he was a
          founding member of the Justice League of America. In the 1990s Modern Age
          of Comic Books, Aquaman's character became more serious than in most
          previous interpretations, with storylines depicting the weight of his role
          as king of Atlantis.[1]

          Publication history

          During the 1930s and 1940s — a period fans and historians call the Golden Age of
          Comic Books — the first version of Aquaman, was created by writer Mort Weisinger
          and artist Paul Norris, appeared in a backup feature in DC Comics' More Fun
          Comics #73-107 (Nov. 1941 - Feb. 1946), after which the series dropped superhero
          stories to become a humor title. Aquaman's feature moved to Adventure Comics
          #103-284 (April 1946 - May 1961) as a backup to the comic book's star, Superboy.

          Shortly after the character's debut, Louis Cazeneuve succeeded Norris to become
          the longest-running artist of the undersea hero's Golden Age adventures.
          Cazeneuve debuted on "Aquaman" in More Fun Comics #82 (Aug. 1942), and continued
          with the feature through issue #107 (Feb. 1946), and its subsequent move to
          Adventure Comics #103-117, 119-120, 124 (April 1946 - June 1947, Aug.-Sept.
          1947, Jan. 1948). The first recurring supporting characters in the feature were
          various sea creatures, including Ark, a pet seal who appeared in several of
          Aquaman's 1940s adventures, and Topo, Aquaman's pet octopus, who first appeared
          in Adventure Comics #229 (Oct. 1956).

          Writer Robert Bernstein and penciler-inker Ramona Fradon, one of the few female
          comic artists of that period, introduced the Silver Age version of Aquaman in
          Adventure Comics #260 (May 1959), providing a new, substantially different
          origin for the character.[2] Bernstein scripted through at least #282 (March
          1961), introducing such major characters as Aqualad and Aquagirl, while Fradon's
          art established the look of Aquaman for several years. Aquaman continued to
          appear in Adventure Comics until issue #284 (May 1961), when the feature moved
          to Detective Comics from issues #293-300 (Jul 1961-Feb 1962), then to World's
          Finest Comics from issues #125-139 (May 1962-Feb 1964).
        FULL_BASE_FILE
        [
          {
            path: "aquaman.txt",
            content: file_one,
          },
        ]
      end
    end
  end
end
