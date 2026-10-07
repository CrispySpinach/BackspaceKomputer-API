fn main() {
    // sqlx::migrate! embeds files; also rebuild when a migration is added.
    println!("cargo:rerun-if-changed=migrations");
}
