#!/usr/bin/env python3
"""Write all commits since the most recently published GitHub release."""
import json
import subprocess
import sys


def git(*args):
    return subprocess.check_output(['git', *args], text=True).strip()


def changelog(releases, repository):
    published = [r for r in releases if not r['draft'] and r.get('published_at')]
    previous = max(published, key=lambda r: r['published_at']) if published else None
    revision = 'HEAD'
    lines = ['## Changes', '']
    if previous:
        tag = previous['tag_name']
        commit = git('rev-parse', '--verify', f'refs/tags/{tag}^{{commit}}')
        subprocess.run(['git', 'merge-base', '--is-ancestor', commit, 'HEAD'], check=True)
        revision = f'{commit}..HEAD'
        lines += [f'Since [{tag}]({previous["html_url"]}).', '']
    else:
        lines += ['First release: includes all commits.', '']
    commits = git('log', '--format=%H %s', revision)
    for entry in commits.splitlines():
        sha, subject = entry.split(' ', 1)
        lines.append(f'- {subject} ([{sha[:7]}](https://github.com/{repository}/commit/{sha}))')
    lines += ['', '## Downloads', '',
              '- AltStore IPA: unsigned; install with your own signing identity using AltStore.',
              '- Mac ZIP: universal arm64/x86_64 app, signed with Developer ID, notarized, '
              'and stapled for direct installation.', '']
    return '\n'.join(lines)


if __name__ == '__main__':
    # gh api --paginate --slurp emits an array of release pages.
    pages = json.load(sys.stdin)
    print(changelog([release for page in pages for release in page], sys.argv[1]))
