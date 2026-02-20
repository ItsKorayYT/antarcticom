fn main() {
    // Compile protobuf definitions (optional — requires protoc)
    if let Err(e) = prost_build::compile_protos(
        &[
            "../proto/messages.proto",
            "../proto/voice.proto",
            "../proto/auth.proto",
            "../proto/events.proto",
        ],
        &["../proto/"],
    ) {
        println!("cargo:warning=Skipping protobuf compilation: {e}");
        println!("cargo:warning=Install protoc if you need proto support.");
    }
}
