CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_documents (
 document_key VARCHAR(80) NOT NULL, version VARCHAR(40) NOT NULL,
 title VARCHAR(200) NOT NULL, body MEDIUMTEXT NOT NULL, required TINYINT NOT NULL DEFAULT 0,
 updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
 PRIMARY KEY(document_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_preferences (
 borrowernumber INT NOT NULL PRIMARY KEY, show_in_leaderboard TINYINT NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_loan_windows (
 request_id INT NOT NULL PRIMARY KEY, proposed_start DATE NULL, proposed_end DATE NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_photos (
 id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, owner_borrowernumber INT NOT NULL,
 listing_id INT NULL, review_id INT NULL, storage_name VARCHAR(80) NOT NULL,
 mime VARCHAR(40) NOT NULL, caption VARCHAR(200) NOT NULL DEFAULT '',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 KEY ls_photo_listing(listing_id), KEY ls_photo_review(review_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_reports (
 id INT NOT NULL AUTO_INCREMENT PRIMARY KEY, listing_id INT NOT NULL,
 reporter_borrowernumber INT NOT NULL, reason VARCHAR(2000) NOT NULL,
 status VARCHAR(20) NOT NULL DEFAULT 'open', resolution VARCHAR(2000) NOT NULL DEFAULT '',
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_roles (
 borrowernumber INT NOT NULL PRIMARY KEY, role VARCHAR(20) NOT NULL DEFAULT 'admin'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_audit (
 id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, actor INT NOT NULL,
 action VARCHAR(80) NOT NULL, target VARCHAR(100) NOT NULL, note VARCHAR(2000) NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_badge_definitions (
 slug VARCHAR(80) NOT NULL PRIMARY KEY, label VARCHAR(200) NOT NULL,
 description VARCHAR(1000) NOT NULL DEFAULT '', family VARCHAR(20) NOT NULL DEFAULT 'community',
 metric VARCHAR(80) NOT NULL, threshold DECIMAL(12,2) NOT NULL, active TINYINT NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_impact_defaults (
 category VARCHAR(80) NOT NULL PRIMARY KEY, retail_value DECIMAL(12,2) NOT NULL,
 co2_kg DECIMAL(12,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_fulfilments (
 wanted_id INT NOT NULL PRIMARY KEY, listing_id INT NOT NULL, lender INT NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_credit_events (
 event_key VARCHAR(120) NOT NULL PRIMARY KEY, patron_id INT NOT NULL, delta INT NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT IGNORE INTO koha_plugin_com_libraryshare_documents(document_key,version,title,body,required) VALUES
 ('help','1','How LibraryShare works','Sign into your library account. List an item you own, or request an available item. Agree a public pickup place and time with the lender. The loan appears in Koha. Return the item to its owner, who confirms its return. Contact library staff to resolve disputes. Never publish private addresses or personal contact details.',0);
INSERT IGNORE INTO koha_plugin_com_libraryshare_documents(document_key,version,title,body,required) VALUES
 ('terms','1','LibraryShare Terms of Service','Sample text — replace before production. Not legal advice.
Welcome to LibraryShare. By using this service you agree to:
1. Use the platform only to lend and borrow personal items with other library patrons at no cost.
2. Provide accurate descriptions of items you list.
3. Return borrowed items in the condition you received them, by the agreed date.
4. Communicate respectfully with other patrons.
5. Not list prohibited items (weapons, illegal goods, perishables, or items requiring a license to operate).
LibraryShare is provided as-is with no warranty. Your library and LibraryShare contributors are not responsible for disputes, damages, or losses arising from peer-to-peer lending.',1),
 ('waiver','1','Peer Lending Waiver & Release','Sample text — replace before production. Not legal advice.
By listing or borrowing items on LibraryShare, I acknowledge and agree:
1. Assumption of risk. All lending and borrowing occurs between individual library patrons. I use, transport, and store borrowed items at my own risk.
2. Release. I release the library, LibraryShare contributors, and other patrons from any claims for injury, property damage, or loss arising from my use of items obtained through this platform.
3. Responsibility as borrower. I am responsible for reasonable care of any item I borrow and for returning it on time. If I damage or lose an item, I will work in good faith with the lender to resolve it.
4. Responsibility as lender. I represent that any item I list is safe for its intended use, that I have the right to lend it, and that I have disclosed any known defects.
5. No insurance. LibraryShare does not provide insurance for lent items.
I have read and understood this waiver.',1);
CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_document_versions (
 document_key VARCHAR(80) NOT NULL, version VARCHAR(40) NOT NULL,
 title VARCHAR(200) NOT NULL, body MEDIUMTEXT NOT NULL,
 published_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
 PRIMARY KEY(document_key,version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT IGNORE INTO koha_plugin_com_libraryshare_document_versions(document_key,version,title,body)
 SELECT document_key,version,title,body FROM koha_plugin_com_libraryshare_documents;
INSERT IGNORE INTO koha_plugin_com_libraryshare_badge_definitions(slug,label,description,family,metric,threshold) VALUES
 ('first_lend','First Lend','Completed your first loan as a lender.','lending','loans_as_lender',1),
 ('loans_10','10 Loans','Completed ten loans.','lending','loans_as_lender',10),
 ('loans_25','25 Loans','Completed twenty-five loans.','lending','loans_as_lender',25),
 ('loans_100','100 Loans','Completed one hundred loans.','lending','loans_as_lender',100),
 ('perfect_streak','Perfect Streak','Ten consecutive five-star lender reviews.','lending','perfect_streak',10),
 ('category_specialist','Category Specialist','Five completed loans in one category.','lending','category_specialist',5),
 ('diversifier','Diversifier','Lent items in four categories.','lending','distinct_categories_lent',4),
 ('long_hauler','Long-Hauler','Completed a loan lasting at least thirty days.','lending','longest_loan_days',30),
 ('community_pillar','Community Pillar','Top ten percent of lenders this month.','community','community_pillar',1),
 ('on_time_returner','On-Time Returner','Returned five items on time.','borrowing','on_time_returns',5),
 ('careful_custodian','Careful Custodian','Ten completed borrows with no disputes.','borrowing','careful_custodian',10),
 ('wish_granter','Wish Granter','Listed an item from the wanted board.','community','wishes_fulfilled',1),
 ('explorer','Explorer','Borrowed from three categories.','borrowing','distinct_categories_borrowed',3);
