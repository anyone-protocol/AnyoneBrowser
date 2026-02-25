#  Anyone Browser Changelog

## 1.1.1

- Fixed bug where `anyonehttp`/`anyonehttps` links wouldn't open right after app start. 

## 1.1.0

- Added bookmarks folder support.
- Added bookmarks import/export with Firefox-compatible HTML file.
- Updated translations.
- Fixed bug where certificate info sometimes wouldn't show.
- Added scheme handler for "anyonehttp" and "anyonehttps", so foreign apps can hand over URL to Anyone Browser.

## 1.0.2

- Fixed leak through share sheet by providing our own metadata acquired through anon.
- Show status summary when bootstrapping anon.
- Improved URL blocker:
  - Replaced outdated blocklist with HaGeZi's list: https://github.com/hagezi/dns-blocklists
  - App ships with light list by default.
  - Updateable by user, 5 different lists to choose from.
  - Optionally switch off completely.

## 1.0.1

- Fixed App Store link.

## 1.0.0

- Initial release
