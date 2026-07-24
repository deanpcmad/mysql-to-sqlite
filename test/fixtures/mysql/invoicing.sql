-- MySQL dump 10.13  Distrib 8.4, for Linux (x86_64)
-- A realistic multi-table invoicing dataset: customers, invoices, line items,
-- quotes and emails, exercising a 3-level foreign key chain and MySQL types
-- (decimal, enum, date/datetime) not covered by the smaller fixtures.

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

CREATE TABLE `customers` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `email` varchar(255) NOT NULL,
  `phone` varchar(50) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `invoices` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `customer_id` bigint NOT NULL,
  `invoice_number` varchar(20) NOT NULL,
  `status` enum('draft','sent','paid','overdue') NOT NULL DEFAULT 'draft',
  `subtotal` decimal(10,2) NOT NULL,
  `tax` decimal(10,2) NOT NULL DEFAULT '0.00',
  `total` decimal(10,2) NOT NULL,
  `issued_on` date NOT NULL,
  `due_at` datetime(6) DEFAULT NULL,
  `notes` text,
  PRIMARY KEY (`id`),
  KEY `index_invoices_on_customer_id` (`customer_id`),
  CONSTRAINT `fk_invoices_customers` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `invoice_line_items` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `invoice_id` bigint NOT NULL,
  `description` varchar(255) NOT NULL,
  `quantity` int NOT NULL DEFAULT '1',
  `unit_price` decimal(10,2) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_invoice_line_items_on_invoice_id` (`invoice_id`),
  CONSTRAINT `fk_invoice_line_items_invoices` FOREIGN KEY (`invoice_id`) REFERENCES `invoices` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `quotes` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `customer_id` bigint NOT NULL,
  `quote_number` varchar(20) NOT NULL,
  `status` enum('draft','sent','accepted','declined') NOT NULL DEFAULT 'draft',
  `total` decimal(10,2) NOT NULL,
  `expires_on` date DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_quotes_on_customer_id` (`customer_id`),
  CONSTRAINT `fk_quotes_customers` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE `emails` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `customer_id` bigint NOT NULL,
  `invoice_id` bigint DEFAULT NULL,
  `subject` varchar(255) NOT NULL,
  `sent_at` datetime(6) NOT NULL,
  `body` text,
  PRIMARY KEY (`id`),
  KEY `index_emails_on_customer_id` (`customer_id`),
  KEY `index_emails_on_invoice_id` (`invoice_id`),
  CONSTRAINT `fk_emails_customers` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`),
  CONSTRAINT `fk_emails_invoices` FOREIGN KEY (`invoice_id`) REFERENCES `invoices` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `schema_migrations` VALUES ('20260724000000');

INSERT INTO `customers` VALUES
  (1,'Amara Okafor','amara@example.com','555-0101','2025-01-05 09:15:00.000000'),
  (2,'Liang Chen','liang@example.com',NULL,'2025-02-10 14:30:00.000000'),
  (3,'Renée Dubois','renee@example.com','555-0110','2025-03-01 08:00:00.000000'),
  (4,'Kwame Mensah','kwame@example.com','555-0199','2025-04-18 16:45:00.000000'),
  (5,'Test Örnek','test@example.com',NULL,'2025-05-22 11:00:00.000000');

INSERT INTO `invoices` VALUES
  (1,1,'INV-1001','paid',500.00,40.00,540.00,'2025-01-10','2025-01-24 00:00:00.000000',NULL),
  (2,1,'INV-1002','sent',120.50,9.64,130.14,'2025-02-01','2025-02-15 00:00:00.000000','Net 14'),
  (3,2,'INV-1003','draft',75.00,0.00,75.00,'2025-02-12',NULL,NULL),
  (4,2,'INV-1004','overdue',300.00,24.00,324.00,'2025-01-02','2025-01-16 00:00:00.000000','Second reminder sent'),
  (5,3,'INV-1005','paid',1157.39,92.59,1249.98,'2025-03-05','2025-03-19 00:00:00.000000',NULL),
  (6,3,'INV-1006','sent',45.00,3.60,48.60,'2025-03-20','2025-04-03 00:00:00.000000',NULL),
  (7,4,'INV-1007','paid',890.00,71.20,961.20,'2025-04-20','2025-05-04 00:00:00.000000',NULL),
  (8,5,'INV-1008','draft',60.00,4.80,64.80,'2025-05-25',NULL,'Awaiting PO number');

INSERT INTO `invoice_line_items` VALUES
  (1,1,'Consulting hours',10,50.00),
  (2,1,'Travel expenses',1,0.00),
  (3,2,'Design mockups',5,20.10),
  (4,2,'Revision round',1,20.00),
  (5,3,'Website audit',1,75.00),
  (6,4,'Monthly retainer',3,100.00),
  (7,4,'Rush fee',1,0.00),
  (8,5,'Software license',1,999.99),
  (9,5,'Support plan',1,100.00),
  (10,5,'Onboarding session',1,57.40),
  (11,6,'Logo design',1,45.00),
  (12,7,'Development sprint',2,400.00),
  (13,7,'QA testing',1,90.00),
  (14,8,'Consultation call',1,60.00),
  (15,8,'Follow-up email',1,0.00);

INSERT INTO `quotes` VALUES
  (1,1,'Q-2001','sent',400.00,'2025-02-01'),
  (2,2,'Q-2002','accepted',220.00,'2025-03-01'),
  (3,4,'Q-2003','declined',150.00,NULL),
  (4,5,'Q-2004','draft',60.00,'2025-06-01');

INSERT INTO `emails` VALUES
  (1,1,1,'Invoice INV-1001 sent','2025-01-10 09:00:00.000000','Please find attached your invoice.'),
  (2,1,NULL,'Welcome aboard','2025-01-05 09:20:00.000000',NULL),
  (3,2,4,'Overdue reminder: INV-1004','2025-02-01 10:00:00.000000','This invoice is overdue.'),
  (4,3,5,'Invoice INV-1005 paid - thank you','2025-03-19 12:00:00.000000',NULL),
  (5,4,NULL,'Quote Q-2003 declined','2025-04-25 15:30:00.000000','We understand, thanks for considering us.'),
  (6,5,8,'Invoice INV-1008 draft ready for review','2025-05-25 09:05:00.000000',NULL);

SET FOREIGN_KEY_CHECKS=1;
