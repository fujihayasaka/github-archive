module SnapshotGenerators
  class Metadata
    def self.gen_push_id
      Rantly { positive_integer }
    end

    def self.gen_sha
      Rantly {
        digits = array(40) { choose("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f") }
        digits.join
      }
    end

    def self.gen_ref
      Rantly {
        digits = array(10) { choose("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f") }
        digits.join
      }
    end

    def self.generate(sha = nil)
      Rantly {
        push_id = SnapshotGenerators::Metadata.gen_push_id
        sha = sha.present? ? sha : SnapshotGenerators::Metadata.gen_sha
        ref = SnapshotGenerators::Metadata.gen_ref

        Snapshots::Metadata.new(push_id: push_id, sha: sha, ref: ref)
      }
    end
  end

  class DependencySnapshotMetadata
    def self.gen_job_id
      Rantly { positive_integer }
    end

    def self.gen_run_id
      Rantly { positive_integer }
    end

    def self.gen_branch_ref
      Rantly {
        digits = array(10) { choose("0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f") }
        digits.join
      }
    end

    def self.generate
      Rantly {
        {
          branch_ref: SnapshotGenerators::DependencySnapshotMetadata.gen_branch_ref,
          job_id: SnapshotGenerators::DependencySnapshotMetadata.gen_job_id,
          run_id: SnapshotGenerators::DependencySnapshotMetadata.gen_run_id
        }
      }
    end
  end
end
