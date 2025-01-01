use std::io::Result;
use std::path::PathBuf;

fn protos() -> Vec<PathBuf> {
    glob::glob("../proto/**/*.proto")
        .expect("io error finding proto files")
        .flatten()
        .collect()
}

fn main() -> Result<()> {
    let proto_source_files = protos();
    for entry in &proto_source_files {
        // Changes in the .proto files must entail changes in generated code
        println!("cargo:rerun-if-changed={}", entry.display());
    }
    let mut prost_build = prost_build::Config::new();
    prost_build
        .service_generator(twirp_build::service_generator())
        // All messages should have Serialize/Deserialize implementations
        .type_attribute(".", "#[derive(serde::Serialize,serde::Deserialize)]")
        // Specify which types we want to delegate to prost_wkt_types
        .extern_path(".google.protobuf.Any", "::prost_wkt_types::Any")
        .extern_path(".google.protobuf.Timestamp", "::prost_wkt_types::Timestamp")
        .extern_path(".google.protobuf.Duration", "::prost_wkt_types::Duration")
        .extern_path(".google.protobuf.Value", "::prost_wkt_types::Value")
        .compile_protos(&proto_source_files, &["../proto"])?;
    Ok(())
}
