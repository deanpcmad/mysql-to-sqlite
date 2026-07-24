-- MySQL dump 10.13  Distrib 8.4, for Linux (x86_64)
-- A representative relational dataset with nulls, Unicode, booleans and binary data.

SET FOREIGN_KEY_CHECKS=0;
DROP TABLE IF EXISTS `legacy_events`;
DROP TABLE IF EXISTS `posts`;
DROP TABLE IF EXISTS `authors`;
DROP TABLE IF EXISTS `schema_migrations`;

CREATE TABLE `schema_migrations` (
  `version` varchar(255) NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `authors` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `biography` text,
  `active` tinyint(1) NOT NULL DEFAULT '1',
  `joined_on` date DEFAULT NULL,
  `token` varbinary(16) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `posts` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `author_id` bigint NOT NULL,
  `title` varchar(255) NOT NULL,
  `body` text,
  `published_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_posts_on_author_id` (`author_id`),
  CONSTRAINT `fk_posts_authors` FOREIGN KEY (`author_id`) REFERENCES `authors` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `schema_migrations` VALUES ('20260724000000');
INSERT INTO `authors` VALUES
  (2,'Ada Lovelace','First programmer',1,'1843-01-01',0x00FF10),
  (7,'Renée O''Connor',NULL,0,NULL,NULL);
INSERT INTO `posts` VALUES
  (3,2,'Notes on the engine','Unicode: π and 🚀','2026-07-24 12:34:56.123456'),
  (9,7,'A nullable post',NULL,NULL);
SET FOREIGN_KEY_CHECKS=1;
