# Releasing tq

## One-time setup: Create a Homebrew tap

1. Create a new GitHub repository: `YOUR_USERNAME/homebrew-tq`

2. Clone it and add the formula:

   ```bash
   git clone https://github.com/YOUR_USERNAME/homebrew-tq.git
   cd homebrew-tq
   mkdir -p Formula
   ```

3. Copy the formula template from this repo:

   ```bash
   cp /path/to/tq/Formula/tq.rb Formula/tq.rb
   ```

4. Edit `Formula/tq.rb` and replace `YOUR_USERNAME` with your actual GitHub username.

5. Commit and push:

   ```bash
   git add Formula/tq.rb
   git commit -m "Add tq formula"
   git push
   ```

## Every release

1. **Tag the release** in the `tq` repo:

   ```bash
   cd /path/to/tq
   git tag v0.2.0
   git push origin v0.2.0
   ```

2. **Compute the tarball SHA256**:

   ```bash
   curl -sL https://github.com/YOUR_USERNAME/tq/archive/refs/tags/v0.2.0.tar.gz | shasum -a 256
   ```

3. **Update the formula** in `homebrew-tq`:

   ```bash
   cd /path/to/homebrew-tq
   ```

   Edit `Formula/tq.rb`:
   - Update the `url` line with the new tag
   - Replace `sha256` with the hash from step 2

4. **Test the formula locally**:

   ```bash
   brew install --build-from-source ./Formula/tq.rb
   brew test tq
   ```

5. Commit and push:

   ```bash
   git add Formula/tq.rb
   git commit -m "tq v0.2.0"
   git push
   ```

Users can now upgrade with `brew upgrade tq`.

## Optional: Pre-built bottles (faster installs)

To eliminate the Swift compile step for users, set up GitHub Actions to build
universal binaries and upload them as `.tar.gz` bottles. Homebrew's
`brew bottle` subcommand automates this. Once bottles are hosted:

```ruby
bottle do
  root_url "https://github.com/YOUR_USERNAME/tq/releases/download/v0.2.0"
  sha256 arm64_ventura: "abc123..."
  sha256 ventura:       "def456..."
end
```

See [Homebrew's Bottle Cookbook](https://docs.brew.sh/Bottles) for details.
