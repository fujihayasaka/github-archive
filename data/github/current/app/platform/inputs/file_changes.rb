# typed: true
# frozen_string_literal: true

module Platform
  module Inputs
    class FileChanges < Platform::Inputs::Base
      graphql_name "FileChanges"
      description <<~'MARKDOWN'
        A description of a set of changes to a file tree to be made as part of
        a git commit, modeled as zero or more file `additions` and zero or more
        file `deletions`.

        Both fields are optional; omitting both will produce a commit with no
        file changes.

        `deletions` and `additions` describe changes to files identified
        by their path in the git tree using unix-style path separators, i.e.
        `/`.  The root of a git tree is an empty string, so paths are not
        slash-prefixed.

        `path` values must be unique across all `additions` and `deletions`
        provided.  Any duplication will result in a validation error.

        ### Encoding

        File contents must be provided in full for each `FileAddition`.

        The `contents` of a `FileAddition` must be encoded using RFC 4648
        compliant base64, i.e. correct padding is required and no characters
        outside the standard alphabet may be used.  Invalid base64
        encoding will be rejected with a validation error.

        The encoded contents may be binary.

        For text files, no assumptions are made about the character encoding of
        the file contents (after base64 decoding).  No charset transcoding or
        line-ending normalization will be performed; it is the client's
        responsibility to manage the character encoding of files they provide.
        However, for maximum compatibility we recommend using UTF-8 encoding
        and ensuring that all files in a repository use a consistent
        line-ending convention (`\n` or `\r\n`), and that all files end
        with a newline.

        ### Modeling file changes

        Each of the the five types of conceptual changes that can be made in a
        git commit can be described using the `FileChanges` type as follows:

        1. New file addition: create file `hello world\n` at path `docs/README.txt`:

               {
                 "additions" [
                   {
                     "path": "docs/README.txt",
                     "contents": base64encode("hello world\n")
                   }
                 ]
               }

        2. Existing file modification: change existing `docs/README.txt` to have new
           content `new content here\n`:

               {
                 "additions" [
                   {
                     "path": "docs/README.txt",
                     "contents": base64encode("new content here\n")
                   }
                 ]
               }

        3. Existing file deletion: remove existing file `docs/README.txt`.
           Note that the path is required to exist -- specifying a
           path that does not exist on the given branch will abort the
           commit and return an error.

               {
                 "deletions" [
                   {
                     "path": "docs/README.txt"
                   }
                 ]
               }


        4. File rename with no changes: rename `docs/README.txt` with
           previous content `hello world\n` to the same content at
           `newdocs/README.txt`:

               {
                 "deletions" [
                   {
                     "path": "docs/README.txt",
                   }
                 ],
                 "additions" [
                   {
                     "path": "newdocs/README.txt",
                     "contents": base64encode("hello world\n")
                   }
                 ]
               }


        5. File rename with changes: rename `docs/README.txt` with
           previous content `hello world\n` to a file at path
           `newdocs/README.txt` with content `new contents\n`:

               {
                 "deletions" [
                   {
                     "path": "docs/README.txt",
                   }
                 ],
                 "additions" [
                   {
                     "path": "newdocs/README.txt",
                     "contents": base64encode("new contents\n")
                   }
                 ]
               }
      MARKDOWN

      argument :deletions, [Inputs::FileDeletion], "Files to delete.", required: false, default_value: []
      argument :additions, [Inputs::FileAddition], "File to add or change.", required: false, default_value: []

      # I imagine there might be a better method to put custom validation in
      # but I'm not quite sure where it should go.  This enforces basic rules
      # like "no duplicate files may be specified"
      # validation_options is a hash with keys: max_errors
      # see: https://graphql-ruby.org/errors/overview.html#validation-errors
      def self.validate_non_null_input(value, ctx, _validation_options = {})
        result = super(value, ctx)
        additions = value["additions"] || []
        deletions = value["deletions"] || []
        paths = (additions + deletions).map { |change| change["path"] }
        unless paths == paths.uniq
          result.add_problem("Paths must be unique across additions and deletions. At least one path was included more than once.")
        end
        result
      end
    end
  end
end
