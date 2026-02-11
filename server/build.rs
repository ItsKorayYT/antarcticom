fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Compile protobuf definitions
    prost_build::compile_protos(
        &[
            "../proto/messages.proto",
            "../proto/voice.proto",
            "../proto/auth.proto",
            "../proto/events.proto",
        ],
        &["../proto/"],
    )?;
    Ok(())
}
