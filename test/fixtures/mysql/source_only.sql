-- MySQL dump containing a leftover table that is intentionally absent from SQLite.

SET FOREIGN_KEY_CHECKS=0;
DROP TABLE IF EXISTS `emails`;
DROP TABLE IF EXISTS `quotes`;
DROP TABLE IF EXISTS `invoice_line_items`;
DROP TABLE IF EXISTS `invoices`;
DROP TABLE IF EXISTS `customers`;
DROP TABLE IF EXISTS `posts`;
DROP TABLE IF EXISTS `legacy_events`;
DROP TABLE IF EXISTS `authors`;
DROP TABLE IF EXISTS `schema_migrations`;

CREATE TABLE `schema_migrations` (
  `version` varchar(255) NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `authors` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `legacy_events` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `payload` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `schema_migrations` VALUES ('20260724000000');
INSERT INTO `authors` VALUES (4,'Grace Hopper');
INSERT INTO `legacy_events` VALUES (1,'safe to ignore in this fixture');
SET FOREIGN_KEY_CHECKS=1;
