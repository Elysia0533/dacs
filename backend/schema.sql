PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  display_name TEXT NOT NULL,
  avatar_url TEXT NOT NULL DEFAULT '',
  role TEXT NOT NULL DEFAULT 'user',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS stories (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  title_eng TEXT NOT NULL DEFAULT '',
  author TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  genres TEXT NOT NULL DEFAULT '[]',
  total_chapters INTEGER NOT NULL DEFAULT 1,
  icon_url TEXT NOT NULL DEFAULT '',
  drive_file_id TEXT NOT NULL DEFAULT '',
  file_type TEXT NOT NULL DEFAULT '',
  is_published INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS user_library (
  user_id TEXT NOT NULL,
  story_id TEXT NOT NULL,
  local_path TEXT NOT NULL DEFAULT '',
  saved_chapter_index INTEGER NOT NULL DEFAULT 0,
  total_chapters INTEGER NOT NULL DEFAULT 1,
  scroll_offset REAL NOT NULL DEFAULT 0,
  last_read_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (user_id, story_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (story_id) REFERENCES stories(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS community_messages (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_stories_title ON stories(title);
CREATE INDEX IF NOT EXISTS idx_stories_author ON stories(author);
CREATE INDEX IF NOT EXISTS idx_library_user ON user_library(user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_messages_created ON community_messages(created_at);
