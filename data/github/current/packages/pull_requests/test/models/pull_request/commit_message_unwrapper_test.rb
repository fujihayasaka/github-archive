# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestCommitMessageUnwrapperTest < GitHub::TestCase
  EXAMPLE_COMMIT_MESSAGE = <<~MESSAGE
    Alice was beginning to get very tired of sitting by her sister on the
    bank, and of having nothing to do: once or twice she had peeped into the
    book her sister was reading, but it had no pictures or conversations in
    it, "and what is the use of a book," thought Alice "without pictures or
    conversations?"

      two-indent multi-line
      here

    Some more words

        four-indent multi-line
        here

    Even more words

    \tindent using tab chars

    - some thing
    - some other thing
    - also this

    Some more words

    1. thing the first
    2. thing the second!
    3. third

    Even more words

    1 abc
    2 dfg
    3 dfgaskhsakjdhaskjdhasjdh

    Short lines not that don't follow a long line
    don't get unwrapped
    because that would look weird.
    They must be short for some reason.

    So she was considering in her own mind (as well as she could, for the
    hot day made her feel very sleepy and stupid), whether the pleasure of
    making a daisy-chain would be worth the trouble of getting up and
    picking the daisies, when suddenly a White Rabbit with pink eyes ran
    close by her.

    \tindent using tab chars
    \tthat spans
    \tmultiple lines

    Some really long numbered paragraphs

    1. Alice was beginning to get very tired of sitting by her sister on the
       bank, and of having nothing to do: once or twice she had peeped into
       the book her sister was reading, but it had no pictures or
       conversations in it, "and what is the use of a book," thought alice
       "without pictures or conversations?"
    2. So she was considering in her own mind (as well as she could, for the
       hot day made her feel very sleepy and stupid), whether the pleasure
       of making a daisy-chain would be worth the trouble of getting up and
       picking the daisies, when suddenly a White Rabbit with pink eyes ran
       close by her.

    Numbering with indents

      1. Alice was beginning to get very tired of sitting by her sister on the
         bank, and of having nothing to do: once or twice she had peeped into
         the book her sister was reading, but it had no pictures or
         conversations in it, "and what is the use of a book," thought alice
         "without pictures or conversations?"
      2. So she was considering in her own mind (as well as she could, for the
         hot day made her feel very sleepy and stupid), whether the pleasure
         of making a daisy-chain would be worth the trouble of getting up and
         picking the daisies, when suddenly a White Rabbit with pink eyes ran
         close by her.

    Numbering with indents and line separators

      1. Alice was beginning to get very tired of sitting by her sister on the
         bank, and of having nothing to do: once or twice she had peeped into
         the book her sister was reading, but it had no pictures or
         conversations in it, "and what is the use of a book," thought alice
         "without pictures or conversations?"

      2. So she was considering in her own mind (as well as she could, for the
         hot day made her feel very sleepy and stupid), whether the pleasure
         of making a daisy-chain would be worth the trouble of getting up and
         picking the daisies, when suddenly a White Rabbit with pink eyes ran
         close by her.

    unordered lists

      - Alice was beginning to get very tired of sitting by her sister on the
        bank, and of having nothing to do: once or twice she had peeped into
        the book her sister was reading, but it had no pictures or
        conversations in it, "and what is the use of a book," thought alice
        "without pictures or conversations?"
      - So she was considering in her own mind (as well as she could, for the
        hot day made her feel very sleepy and stupid), whether the pleasure
        of making a daisy-chain would be worth the trouble of getting up and
        picking the daisies, when suddenly a White Rabbit with pink eyes ran
        close by her.
  MESSAGE

  EXPECTED_UNWRAPPED = <<~EXPECTED.chomp
    Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, "and what is the use of a book," thought Alice "without pictures or conversations?"

      two-indent multi-line
      here

    Some more words

        four-indent multi-line
        here

    Even more words

    \tindent using tab chars

    - some thing
    - some other thing
    - also this

    Some more words

    1. thing the first
    2. thing the second!
    3. third

    Even more words

    1 abc
    2 dfg
    3 dfgaskhsakjdhaskjdhasjdh

    Short lines not that don't follow a long line
    don't get unwrapped
    because that would look weird.
    They must be short for some reason.

    So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.

    \tindent using tab chars
    \tthat spans
    \tmultiple lines

    Some really long numbered paragraphs

    1. Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, "and what is the use of a book," thought alice "without pictures or conversations?"
    2. So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.

    Numbering with indents

      1. Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, "and what is the use of a book," thought alice "without pictures or conversations?"
      2. So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.

    Numbering with indents and line separators

      1. Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, "and what is the use of a book," thought alice "without pictures or conversations?"

      2. So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.

    unordered lists

      - Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, "and what is the use of a book," thought alice "without pictures or conversations?"
      - So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.
  EXPECTED

  # Most of the test cases for this suite are embedded in the large example
  # message above and asserted implicitly here.
  test "it wraps text at 72 chars, ignoring anything indented, handling lists nicely" do
    assert_unwrap EXPECTED_UNWRAPPED, EXAMPLE_COMMIT_MESSAGE
  end

  test "handles email-ish trailers appropriately" do
    message = <<~MESSAGE
      "git p4" working on UTF-16 files on Windows did not implement
      CRLF-to-LF conversion correctly, which has been corrected.
      source: <pull.1294.v2.git.git.1658341065221.gitgitgadget@gmail.com>

      Signed-off-by: Foo Bar <foobar@longemailongemailongemail.com>
      Reviewed-by: Baz Qux <baz@qux123123123123123123123.com>
      Short-trailer-by: yep
      Co-authored-by: Someone <someone123123123123123123@gmail.com>
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      "git p4" working on UTF-16 files on Windows did not implement CRLF-to-LF conversion correctly, which has been corrected.
      source: <pull.1294.v2.git.git.1658341065221.gitgitgadget@gmail.com>

      Signed-off-by: Foo Bar <foobar@longemailongemailongemail.com>
      Reviewed-by: Baz Qux <baz@qux123123123123123123123.com>
      Short-trailer-by: yep
      Co-authored-by: Someone <someone123123123123123123@gmail.com>
    EXPECTED
  end

  test "handles true trailers properly" do
    message = <<~MESSAGE
      There was a bug in the codepath to upgrade generation information
      in commit-graph from v1 to v2 format, which has been corrected.
      source: <cover.1657667404.git.me@ttaylorr.com>

      * tb/commit-graph-genv2-upgrade-fix:
        commit-graph: fix corrupt upgrade from generation v1 to v2
        commit-graph: introduce `repo_find_commit_pos_in_graph()`
        t5318: demonstrate commit-graph generation v2 corruption
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      There was a bug in the codepath to upgrade generation information in commit-graph from v1 to v2 format, which has been corrected.
      source: <cover.1657667404.git.me@ttaylorr.com>

      * tb/commit-graph-genv2-upgrade-fix:
        commit-graph: fix corrupt upgrade from generation v1 to v2
        commit-graph: introduce `repo_find_commit_pos_in_graph()`
        t5318: demonstrate commit-graph generation v2 corruption
    EXPECTED
  end

  test "it doesn't detect line separators as list chars" do
    message = <<~MESSAGE
      The `p2000` tests demonstrate a ~92% execution time reduction for
      'git rm' using a sparse index.

      ----
      Also, normalize a behavioral difference of `git-rm` under sparse-index.
      See related discussion [1].
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      The `p2000` tests demonstrate a ~92% execution time reduction for 'git rm' using a sparse index.

      ----
      Also, normalize a behavioral difference of `git-rm` under sparse-index. See related discussion [1].
    EXPECTED
  end

  test "list item edge case" do
    message = <<~MESSAGE
      The name of the variable is wrong, and it can be set to anything, like
      1.
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      The name of the variable is wrong, and it can be set to anything, like 1.
    EXPECTED
  end

  test "it detects tables and figures and disables unwrapping for them" do
    message = <<~'MESSAGE'
      The `p2000` tests demonstrate a ~92% execution time reduction for
      'git rm' using a sparse index.

      Test                              HEAD~1            HEAD
      --------------------------------------------------------------------------
      2000.74: git rm ... (full-v3)     0.41(0.37+0.05)   0.43(0.36+0.07) +4.9%
      2000.75: git rm ... (full-v4)     0.38(0.34+0.05)   0.39(0.35+0.05) +2.6%
      2000.76: git rm ... (sparse-v3)   0.57(0.56+0.01)   0.05(0.05+0.00) -91.2%
      2000.77: git rm ... (sparse-v4)   0.57(0.55+0.02)   0.03(0.03+0.00) -94.7%

      Also, normalize a behavioral difference of `git-rm` under sparse-index.
      See related discussion [1].

      | Input     | Output (env A) | Output (env B)   | same/different |
      |-----------+----------------+------------------+----------------|
      | \{<foo>\} | {&lt;foo&gt;}  | \{&lt;foo&gt;}^M | different      |
      | {<foo>}   | {&lt;foo&gt;}  | {&lt;foo&gt;}    | same           |
      | \{<foo>}  | {&lt;foo&gt;}  | \{&lt;foo&gt;}^M | different      |
      | \{foo\}   | {foo}          | {foo}            | same           |
      | \{\}      | {}             | \{}^M            | different      |
      | \{}       | {}             | {}               | same           |
      | {\}       | {}             | {}               | same           |

      Also, normalize a behavioral difference of `git-rm` under sparse-index.
      See related discussion [1].
    MESSAGE

    assert_unwrap <<~'EXPECTED', message
      The `p2000` tests demonstrate a ~92% execution time reduction for 'git rm' using a sparse index.

      Test                              HEAD~1            HEAD
      --------------------------------------------------------------------------
      2000.74: git rm ... (full-v3)     0.41(0.37+0.05)   0.43(0.36+0.07) +4.9%
      2000.75: git rm ... (full-v4)     0.38(0.34+0.05)   0.39(0.35+0.05) +2.6%
      2000.76: git rm ... (sparse-v3)   0.57(0.56+0.01)   0.05(0.05+0.00) -91.2%
      2000.77: git rm ... (sparse-v4)   0.57(0.55+0.02)   0.03(0.03+0.00) -94.7%

      Also, normalize a behavioral difference of `git-rm` under sparse-index. See related discussion [1].

      | Input     | Output (env A) | Output (env B)   | same/different |
      |-----------+----------------+------------------+----------------|
      | \{<foo>\} | {&lt;foo&gt;}  | \{&lt;foo&gt;}^M | different      |
      | {<foo>}   | {&lt;foo&gt;}  | {&lt;foo&gt;}    | same           |
      | \{<foo>}  | {&lt;foo&gt;}  | \{&lt;foo&gt;}^M | different      |
      | \{foo\}   | {foo}          | {foo}            | same           |
      | \{\}      | {}             | \{}^M            | different      |
      | \{}       | {}             | {}               | same           |
      | {\}       | {}             | {}               | same           |

      Also, normalize a behavioral difference of `git-rm` under sparse-index. See related discussion [1].
    EXPECTED
  end

  test "regression of tricky code listing that was being detected as a list partway through" do
    message = <<~'MESSAGE'
      This sort of thing could be detected automatically with a rule similar
      to the unused.cocci merged in 7fa60d2a5b6 (Merge branch
      'ab/cocci-unused' into next, 2022-07-11). The following rule on top
      would catch the case being fixed here:

              @@
              type T;
              identifier I;
              identifier REL1 =~ "^[a-z_]*_(release|reset|clear|free)$";
              identifier REL2 =~ "^(release|clear|free)_[a-z_]*$";
              @@

              - memset(\( I \| &I \), 0, ...);
                ... when != \( I \| &I \)
              (
                \( REL1 \| REL2 \)( \( I \| &I \), ...);
              |
                \( REL1 \| REL2 \)( \( &I \| I \) );
              )
                ... when != \( I \| &I \)

      That rule should arguably use only &I, not I (as we might be passed a
      pointer). The distinction would matter if anyone cared about the
      side-effects of a memset() followed by release() of a pointer to a
      variable passed into the function.
    MESSAGE

    assert_unwrap <<~'EXPECTED', message
      This sort of thing could be detected automatically with a rule similar to the unused.cocci merged in 7fa60d2a5b6 (Merge branch 'ab/cocci-unused' into next, 2022-07-11). The following rule on top would catch the case being fixed here:

              @@
              type T;
              identifier I;
              identifier REL1 =~ "^[a-z_]*_(release|reset|clear|free)$";
              identifier REL2 =~ "^(release|clear|free)_[a-z_]*$";
              @@

              - memset(\( I \| &I \), 0, ...);
                ... when != \( I \| &I \)
              (
                \( REL1 \| REL2 \)( \( I \| &I \), ...);
              |
                \( REL1 \| REL2 \)( \( &I \| I \) );
              )
                ... when != \( I \| &I \)

      That rule should arguably use only &I, not I (as we might be passed a pointer). The distinction would matter if anyone cared about the side-effects of a memset() followed by release() of a pointer to a variable passed into the function.
    EXPECTED
  end

  test "handles multi-paragraph list items" do
    # The second list item is two paragraphs long and should be detected as
    # such and rendered in a way that looks good in markdown.
    message = <<~MESSAGE
      Why do we miss these leaks? Because:

       * We have leaks inside "test_expect_failure" blocks, which by design
         will not distinguish a "normal" failure from an abort() or
         segfault. See [1] for a discussion of it shortcomings.

       * Our tests will otherwise catch segfaults and abort(), but if we
         invoke a command that invokes another command it needs to ferry the
         exit code up to us.

         Notably a command that e.g. might invoke "git pack-objects" might
         itself exit with status 128 if that "pack-objects" segfaults or
         abort()'s. If the test invoking the parent command(s) is using
         "test_must_fail" we'll consider it an expected "ok" failure.

       * run-command.c doesn't (but probably should) ferry up such exit
         codes, so for e.g. "git push" tests where we expect a failure and an
         underlying "git" command fails we won't ferry up the segfault or
         abort exit code.

      A few notes:

        - We use REFNAME_ALLOW_ONELEVEL here, which lets:

              git update-ref refs/heads/foo FETCH_HEAD

          continue to work. It's unclear whether anybody wants to do something
          so odd, but it does work now, so this is erring on the conservative
          side. There's a test to make sure we didn't accidentally break this,
          but don't take that test as an endorsement that it's a good idea, or
          something we might not change in the future.

        - The test in t4202-log.sh checks how we handle such an invalid ref on
          the reading side, so it has to be updated to touch the HEAD file
          directly.
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      Why do we miss these leaks? Because:

       * We have leaks inside "test_expect_failure" blocks, which by design will not distinguish a "normal" failure from an abort() or segfault. See [1] for a discussion of it shortcomings.

       * Our tests will otherwise catch segfaults and abort(), but if we invoke a command that invokes another command it needs to ferry the exit code up to us.

         Notably a command that e.g. might invoke "git pack-objects" might itself exit with status 128 if that "pack-objects" segfaults or abort()'s. If the test invoking the parent command(s) is using "test_must_fail" we'll consider it an expected "ok" failure.

       * run-command.c doesn't (but probably should) ferry up such exit codes, so for e.g. "git push" tests where we expect a failure and an underlying "git" command fails we won't ferry up the segfault or abort exit code.

      A few notes:

        - We use REFNAME_ALLOW_ONELEVEL here, which lets:

              git update-ref refs/heads/foo FETCH_HEAD

          continue to work. It's unclear whether anybody wants to do something so odd, but it does work now, so this is erring on the conservative side. There's a test to make sure we didn't accidentally break this, but don't take that test as an endorsement that it's a good idea, or something we might not change in the future.

        - The test in t4202-log.sh checks how we handle such an invalid ref on the reading side, so it has to be updated to touch the HEAD file directly.
    EXPECTED
  end

  test "disables unwrapping inside fences" do
    message = <<~MESSAGE
      While creating an object, we will be able to fetch the uploader just
      fine:

      ```
      > c = CodeqlVariantAnalysisRepoTask.create(...., uploader: @owner)
      > c.uploader
      <User ...>
      ```

      When `safe-ruby` is executed outside of the RAILS_ROOT directory it fails to
      find the `config/ruby-version` script, e.g.

      ```
      $ bin/vendor-gem https://github.com/github/serviceowners
      Cloning https://github.com/github/serviceowners for gem build
      Building serviceowners
      HEAD is now at 3c5a3fe Merge pull request #67 from github/match-no-reviews
      commit 3c5a3fe4aa352bc5a3557c7ff94aca0415a08f3f (HEAD -> main, tag: v0.11.0)
      Merge: f562294 f90bcc2
      Author: Matt Clark <44023+mclark@users.noreply.github.com>
      Date:   Tue Aug 16 08:41:16 2022 -0400

          Merge pull request #67 from github/match-no-reviews

          Output just path with no owners for pattern specs with `no_review` specified
      /workspaces/github/tmp/gems/serviceowners /workspaces/github/tmp/gems/serviceowners
      Building serviceowners.gemspec
      /workspaces/github/bin/safe-ruby-quick: line 14: config/ruby-version: No such file or directory
      ```

      This commit resolves the problem by using an absolute path when invoking the
      `config/ruby-version` script.

      ```
      PATCH /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{variant_analysis_id}
      ```
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      While creating an object, we will be able to fetch the uploader just fine:

      ```
      > c = CodeqlVariantAnalysisRepoTask.create(...., uploader: @owner)
      > c.uploader
      <User ...>
      ```

      When `safe-ruby` is executed outside of the RAILS_ROOT directory it fails to find the `config/ruby-version` script, e.g.

      ```
      $ bin/vendor-gem https://github.com/github/serviceowners
      Cloning https://github.com/github/serviceowners for gem build
      Building serviceowners
      HEAD is now at 3c5a3fe Merge pull request #67 from github/match-no-reviews
      commit 3c5a3fe4aa352bc5a3557c7ff94aca0415a08f3f (HEAD -> main, tag: v0.11.0)
      Merge: f562294 f90bcc2
      Author: Matt Clark <44023+mclark@users.noreply.github.com>
      Date:   Tue Aug 16 08:41:16 2022 -0400

          Merge pull request #67 from github/match-no-reviews

          Output just path with no owners for pattern specs with `no_review` specified
      /workspaces/github/tmp/gems/serviceowners /workspaces/github/tmp/gems/serviceowners
      Building serviceowners.gemspec
      /workspaces/github/bin/safe-ruby-quick: line 14: config/ruby-version: No such file or directory
      ```

      This commit resolves the problem by using an absolute path when invoking the `config/ruby-version` script.

      ```
      PATCH /repos/{owner}/{repo}/code-scanning/codeql/variant-analyses/{variant_analysis_id}
      ```
    EXPECTED
  end

  test "list item nesting (no spacing)" do
    message = <<~MESSAGE
      Disadvantages:
      - No visible organisation of the file contents. This means
        - Hard to tell which functions are utility functions and which are
          available to you in a debugging session
        - Lots of code duplication within lldb functions Lots of code
          duplication within lldb functions Lots of code duplication within
          lldb functions Lots of code duplication within lldb functions
          - Yard to tell which functions are utility functions and which are
            available to you in a debugging session
          - Xard to tell which functions are utility functions and which are
            available to you in a debugging session
        - Lots of code duplication within lldb functions Lots of code
          duplication within lldb functions Lots of code duplication within
          lldb functions Lots of code duplication within lldb functions
      - Large files quickly become intimidating to work with
        - for example, `lldb_disasm.py` was implemented as a seperate
          Python module because it was easier to start with a clean slate
          than add significant amounts of code to `lldb_cruby.py`
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      Disadvantages:
      - No visible organisation of the file contents. This means
        - Hard to tell which functions are utility functions and which are available to you in a debugging session
        - Lots of code duplication within lldb functions Lots of code duplication within lldb functions Lots of code duplication within lldb functions Lots of code duplication within lldb functions
          - Yard to tell which functions are utility functions and which are available to you in a debugging session
          - Xard to tell which functions are utility functions and which are available to you in a debugging session
        - Lots of code duplication within lldb functions Lots of code duplication within lldb functions Lots of code duplication within lldb functions Lots of code duplication within lldb functions
      - Large files quickly become intimidating to work with
        - for example, `lldb_disasm.py` was implemented as a seperate Python module because it was easier to start with a clean slate than add significant amounts of code to `lldb_cruby.py`
    EXPECTED
  end

  test "list item nesting (with spacing)" do
    message = <<~MESSAGE
      Disadvantages:
      - No visible organisation of the file contents. This means

        - Hard to tell which functions are utility functions and which are
          available to you in a debugging session

        - Lots of code duplication within lldb functions Lots of code
          duplication within lldb functions Lots of code duplication within
          lldb functions Lots of code duplication within lldb functions

          - Yard to tell which functions are utility functions and which are
            available to you in a debugging session

          - Xard to tell which functions are utility functions and which are
            available to you in a debugging session

        - Lots of code duplication within lldb functions Lots of code
          duplication within lldb functions Lots of code duplication within
          lldb functions Lots of code duplication within lldb functions

      - Large files quickly become intimidating to work with

        - for example, `lldb_disasm.py` was implemented as a seperate
          Python module because it was easier to start with a clean slate
          than add significant amounts of code to `lldb_cruby.py`
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      Disadvantages:
      - No visible organisation of the file contents. This means

        - Hard to tell which functions are utility functions and which are available to you in a debugging session

        - Lots of code duplication within lldb functions Lots of code duplication within lldb functions Lots of code duplication within lldb functions Lots of code duplication within lldb functions

          - Yard to tell which functions are utility functions and which are available to you in a debugging session

          - Xard to tell which functions are utility functions and which are available to you in a debugging session

        - Lots of code duplication within lldb functions Lots of code duplication within lldb functions Lots of code duplication within lldb functions Lots of code duplication within lldb functions

      - Large files quickly become intimidating to work with

        - for example, `lldb_disasm.py` was implemented as a seperate Python module because it was easier to start with a clean slate than add significant amounts of code to `lldb_cruby.py`
    EXPECTED
  end

  test "quote chars are ignored" do
    message = <<~MESSAGE
      test: add stuff

      As @wincent said [here](http://example.com/):

      > Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do
      > eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut
      > enim ad minim veniam, quis nostrud exercitation ullamco laboris
      > nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in
      >
      > reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla
      > pariatur. Excepteur sint occaecat cupidatat non proident, sunt in

      > culpa qui officia deserunt mollit anim id est laborum.

      Anyway. That is all.
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      test: add stuff

      As @wincent said [here](http://example.com/):

      > Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do
      > eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut
      > enim ad minim veniam, quis nostrud exercitation ullamco laboris
      > nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in
      >
      > reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla
      > pariatur. Excepteur sint occaecat cupidatat non proident, sunt in

      > culpa qui officia deserunt mollit anim id est laborum.

      Anyway. That is all.
    EXPECTED
  end

  test "reported bad unwrap" do
    message = <<~MESSAGE
      Do something

      Blah blah when I did [1] I didn't know that blah blah in [2] and then
      blah blah blah so that blabh blabh blah. An illustration of why [1]
      was blah blah blah:

      Fixes: 1234567 ("Blah blah blah blaha blah blah (#1234)")
      Some other thing: https://whatever/some/url/goes/here etc
      Resolves: LLL-123 https://some/long/url/here and some other stuff
      Fixes: 9876543 ("Other blah blah blah blah (#1111))
      Amends: LLL-321

      [1] 111111111111 ("xxxxxx xxxxxxxx xxxxx xxxxxx xxxxxxx xxxxxxx xxxxxxxx (#123)")
      [2] 222222222222 ("xxxxxxxxxx xxxxnxxxn xxxxx xxxxxxx xxxxxx (#124)")
    MESSAGE

    assert_unwrap <<~EXPECTED, message
      Do something

      Blah blah when I did [1] I didn't know that blah blah in [2] and then blah blah blah so that blabh blabh blah. An illustration of why [1] was blah blah blah:

      Fixes: 1234567 ("Blah blah blah blaha blah blah (#1234)")
      Some other thing: https://whatever/some/url/goes/here etc
      Resolves: LLL-123 https://some/long/url/here and some other stuff
      Fixes: 9876543 ("Other blah blah blah blah (#1111))
      Amends: LLL-321

      [1] 111111111111 ("xxxxxx xxxxxxxx xxxxx xxxxxx xxxxxxx xxxxxxx xxxxxxxx (#123)")
      [2] 222222222222 ("xxxxxxxxxx xxxxnxxxn xxxxx xxxxxxx xxxxxx (#124)")
    EXPECTED
  end

  test "rejects false positives for trailers" do
    message = <<~MESSAGE
      Blah blah: This should not be detected as a trailer just because it
      has a colon. Neither should this line: a colon is not enough, it has to
      be part of a group of lines that all match as trailers.

      Fixes: 1234567 This is a real trailer.
      This too: yes indeed
      Resolves: LLL-123 https://some/long/url/here and some other stuff
      Fixes: 9876543 ("Other blah blah blah blah (#1111))
      Amends: LLL-321

      [1] 111111111111 This is also a trailer.
      [2] 222222222222 This too.
    MESSAGE
    assert_unwrap <<~EXPECTED, message
      Blah blah: This should not be detected as a trailer just because it has a colon. Neither should this line: a colon is not enough, it has to be part of a group of lines that all match as trailers.

      Fixes: 1234567 This is a real trailer.
      This too: yes indeed
      Resolves: LLL-123 https://some/long/url/here and some other stuff
      Fixes: 9876543 ("Other blah blah blah blah (#1111))
      Amends: LLL-321

      [1] 111111111111 This is also a trailer.
      [2] 222222222222 This too.
    EXPECTED
  end


  private

  def assert_unwrap(expected, text)
    actual = PullRequest::CommitMessageUnwrapper.new(text).call
    assert_equal expected.chomp, actual, "expected:\n#{expected}actual:\n#{actual}"
  end
end
