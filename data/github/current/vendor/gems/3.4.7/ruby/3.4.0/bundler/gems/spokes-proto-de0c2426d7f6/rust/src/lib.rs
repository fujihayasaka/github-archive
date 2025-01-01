pub mod github {
    pub mod spokes {
        // Common types used by all RPCs.
        pub mod types {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.types.v1.rs"));
            }

            pub mod selectors {
                pub mod v1 {
                    include!(concat!(
                        env!("OUT_DIR"),
                        "/github.spokes.types.selectors.v1.rs"
                    ));
                }
            }
        }

        // The various API endpoints
        pub mod backups {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.backups.v1.rs"));
            }
        }
        pub mod batch {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.batch.v1.rs"));
            }
        }
        pub mod blobs {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.blobs.v1.rs"));
            }
        }
        pub mod commits {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.commits.v1.rs"));
            }
        }
        pub mod diffs {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.diffs.v1.rs"));
            }
            pub mod v2 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.diffs.v2.rs"));
            }
        }
        pub mod experimental {
            pub mod v1 {
                include!(concat!(
                    env!("OUT_DIR"),
                    "/github.spokes.experimental.v1.rs"
                ));
            }
        }
        pub mod merges {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.merges.v1.rs"));
            }
        }
        pub mod objects {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.objects.v1.rs"));
            }
        }
        pub mod references {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.references.v1.rs"));
            }
        }
        pub mod trees {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.trees.v1.rs"));
            }
        }
        pub mod submodules {
            pub mod v1 {
                include!(concat!(env!("OUT_DIR"), "/github.spokes.submodules.v1.rs"));
            }
        }
    }
}
