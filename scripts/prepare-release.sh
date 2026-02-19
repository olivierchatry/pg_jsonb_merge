#!/bin/bash
# prepare-release.sh - Script to prepare a release locally

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if version is provided
if [ -z "$1" ]; then
    print_error "Usage: $0 <version>"
    print_error "Example: $0 v1.0.0"
    exit 1
fi

VERSION="$1"
print_status "Preparing release $VERSION"

# Check if we're in a git repository
if [ ! -d ".git" ]; then
    print_error "This script must be run from the root of the git repository"
    exit 1
fi

# Check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
    print_warning "Working directory is not clean. Uncommitted changes:"
    git status --short
    read -p "Continue anyway? [y/N]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Update version in control file if needed
CONTROL_FILE="jsonb_merge.control"
if [ -f "$CONTROL_FILE" ]; then
    current_version=$(grep "default_version" "$CONTROL_FILE" | cut -d"'" -f2)
    print_status "Current version in control file: $current_version"
    
    # Remove 'v' prefix if present for version comparison
    clean_version="${VERSION#v}"
    
    if [ "$current_version" != "$clean_version" ]; then
        print_status "Updating version in $CONTROL_FILE from $current_version to $clean_version"
        sed -i '' "s/default_version = '.*'/default_version = '$clean_version'/" "$CONTROL_FILE"
    fi
fi

# Run tests before creating release
print_status "Running tests..."
if [ -x "./test/docker-test.sh" ]; then
    echo "n" | ./test/docker-test.sh > /tmp/test_output.log 2>&1
    if [ $? -eq 0 ]; then
        print_success "All tests passed"
    else
        print_error "Tests failed. Check /tmp/test_output.log for details"
        tail -20 /tmp/test_output.log
        exit 1
    fi
else
    print_warning "Test script not found or not executable"
fi

# Create release notes template
RELEASE_NOTES="RELEASE_NOTES_${VERSION}.md"
if [ ! -f "$RELEASE_NOTES" ]; then
    print_status "Creating release notes: $RELEASE_NOTES"

    # Find the previous tag to generate changelog
    PREV_TAG=$(git describe --tags --abbrev=0 HEAD 2>/dev/null || echo "")
    if [ -n "$PREV_TAG" ]; then
        CHANGELOG=$(git --no-pager log "${PREV_TAG}..HEAD" --pretty=format:"- %s (%h)" 2>/dev/null)
        DIFF_RANGE="${PREV_TAG}..HEAD"
    else
        CHANGELOG=$(git --no-pager log --pretty=format:"- %s (%h)" 2>/dev/null)
        DIFF_RANGE=""
    fi

    # Categorize commits
    FEATURES=$(echo "$CHANGELOG" | grep -iE "^- (feat|add|support)" || true)
    FIXES=$(echo "$CHANGELOG" | grep -iE "^- (fix|bug|patch|hotfix)" || true)
    PERF=$(echo "$CHANGELOG" | grep -iE "^- (perf|optim|bench|speed)" || true)
    CHORE=$(echo "$CHANGELOG" | grep -iE "^- (chore|doc|ci|refactor|merge|style|test)" || true)

    cat > "$RELEASE_NOTES" << EOF
# Release Notes for $VERSION

## What's Changed${PREV_TAG:+ (since $PREV_TAG)}

EOF

    {
        if [ -n "$FEATURES" ]; then
            echo "### Features"
            echo "$FEATURES"
            echo ""
        fi
        if [ -n "$FIXES" ]; then
            echo "### Bug Fixes"
            echo "$FIXES"
            echo ""
        fi
        if [ -n "$PERF" ]; then
            echo "### Performance"
            echo "$PERF"
            echo ""
        fi
        if [ -n "$CHORE" ]; then
            echo "### Maintenance"
            echo "$CHORE"
            echo ""
        fi
    } >> "$RELEASE_NOTES"

    cat >> "$RELEASE_NOTES" << EOF
## PostgreSQL Compatibility
- [x] PostgreSQL 12
- [x] PostgreSQL 13
- [x] PostgreSQL 14
- [x] PostgreSQL 15
- [x] PostgreSQL 16
- [x] PostgreSQL 17
- [x] PostgreSQL 18

## Breaking Changes
- None

## Installation
Download the appropriate archive for your PostgreSQL version from the release assets.

## Verification
\`\`\`sql
SELECT jsonb_merge('{"a": 1}', '{"b": 2}');
-- Expected: {"a": 1, "b": 2}
\`\`\`
EOF
    print_success "Release notes created. Please review $RELEASE_NOTES"
fi

# Check if tag already exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    print_error "Tag $VERSION already exists"
    exit 1
fi

# Create and push tag
print_status "Creating git tag $VERSION"
git add .
git commit -m "Prepare release $VERSION" || print_warning "Nothing to commit"

git tag -a "$VERSION" -m "Release $VERSION"

print_success "Release preparation completed!"
print_status "Next steps:"
echo "  1. Review and edit $RELEASE_NOTES"
echo "  2. Push the tag to trigger GitHub Actions:"
echo "     git push origin $VERSION"
echo "  3. GitHub Actions will:"
echo "     - Run tests on all PostgreSQL versions"
echo "     - Build binaries for each version"
echo "     - Create a GitHub release with archives"
echo "  4. Review the generated release on GitHub"

# Optionally push immediately
read -p "Push tag now? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Pushing tag $VERSION..."
    git push origin "$VERSION"
    print_success "Tag pushed! Check GitHub Actions for build progress."
    print_status "GitHub Actions URL: https://github.com/$(git remote get-url origin | sed 's/.*github.com[\/:]//;s/.git$//')/actions"
fi
