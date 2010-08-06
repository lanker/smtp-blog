#!/bin/bash

sqlite3 blog.db <<SQL
  CREATE TABLE posts (
    id INTEGER PRIMARY KEY,
    timestamp INTEGER,
    title TEXT,
    text TEXT,
    files TEXT,
    longitude TEXT,
    latitude TEXT,
    altitude TEXT,
    accuracy TEXT,
    position_name TEXT,
    tags TEXT,
    user TEXT,
    image_timestamp INTEGER
  );
SQL

sqlite3 blog.db <<SQL
  CREATE TABLE comments (
    id INTEGER PRIMARY KEY,
    post_id INTEGER,
    timestamp INTEGER,
    text TEXT,
    name TEXT
  );
SQL
