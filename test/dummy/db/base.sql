CREATE TABLE `property_definitions` (
  `property_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `property_owner` varchar(50) NOT NULL,
  `property_name` varchar(50) NOT NULL,
  `property_type` enum('INT','FLOAT','BOOL','STRING','DATE','TIMESTAMP') NOT NULL DEFAULT 'STRING',
  `default_value` varchar(512) DEFAULT NULL,
  `description` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`property_id`),
  UNIQUE KEY `property_owner` (`property_owner`,`property_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `my_models` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE `my_model_properties` (
  `my_model_id` int(11) unsigned NOT NULL,
  `property_id` bigint(20) unsigned NOT NULL,
  `seq_no` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `property_value` varchar(512) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`my_model_id`,`property_id`,`seq_no`),
  KEY `my_model_id` (`my_model_id`),
  CONSTRAINT `my_model_properties_ibfk_1` FOREIGN KEY (`my_model_id`) REFERENCES `my_models` (`id`) ON DELETE CASCADE,
  CONSTRAINT `my_model_properties_ibfk_2` FOREIGN KEY (`property_id`) REFERENCES `property_definitions` (`property_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8;