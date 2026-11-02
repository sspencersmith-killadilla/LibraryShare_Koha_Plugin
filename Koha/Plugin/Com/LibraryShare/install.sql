CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_listings (
    id INT NOT NULL AUTO_INCREMENT,
    owner_borrowernumber INT NOT NULL,
    title VARCHAR(200) NOT NULL,
    author VARCHAR(200) NOT NULL DEFAULT '',
    category VARCHAR(80) NOT NULL,
    estimated_value DECIMAL(10,2) NULL DEFAULT NULL,
    description TEXT NOT NULL,
    item_condition VARCHAR(40) NOT NULL DEFAULT 'good',
    photo_path VARCHAR(255) NULL,
    pickup_branch VARCHAR(10) NOT NULL,
    pickup_location VARCHAR(200) NOT NULL DEFAULT '',
    default_loan_days INT NOT NULL DEFAULT 14,
    biblionumber INT NULL,
    itemnumber INT NULL,
    status ENUM('active','paused','removed') NOT NULL DEFAULT 'active',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ls_owner_status (owner_borrowernumber, status),
    KEY ls_status_created (status, created_at),
    KEY ls_itemnumber (itemnumber)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_borrow_requests (
    id INT NOT NULL AUTO_INCREMENT,
    listing_id INT NOT NULL,
    owner_borrowernumber INT NOT NULL,
    borrower_borrowernumber INT NOT NULL,
    status ENUM('pending','accepted','approved','returned','declined','cancelled') NOT NULL DEFAULT 'pending',
    borrower_message VARCHAR(1000) NOT NULL DEFAULT '',
    lender_message VARCHAR(1000) NOT NULL DEFAULT '',
    pickup_slot_id INT NULL,
    checkout_id INT NULL,
    due_date DATETIME NULL,
    returned_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ls_request_borrower (borrower_borrowernumber, status),
    KEY ls_request_owner (owner_borrowernumber, status),
    KEY ls_request_listing (listing_id, status),
    CONSTRAINT ls_request_listing_fk FOREIGN KEY (listing_id) REFERENCES koha_plugin_com_libraryshare_listings(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_pickup_slots (
    id INT NOT NULL AUTO_INCREMENT,
    listing_id INT NOT NULL,
    owner_borrowernumber INT NOT NULL,
    starts_at DATETIME NOT NULL,
    ends_at DATETIME NOT NULL,
    branchcode VARCHAR(10) NOT NULL,
    location VARCHAR(200) NOT NULL,
    status ENUM('open','booked','cancelled') NOT NULL DEFAULT 'open',
    request_id INT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ls_slot_open (listing_id, status, starts_at),
    KEY ls_slot_owner (owner_borrowernumber, starts_at),
    CONSTRAINT ls_slot_listing_fk FOREIGN KEY (listing_id) REFERENCES koha_plugin_com_libraryshare_listings(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_handoff_events (
    id INT NOT NULL AUTO_INCREMENT,
    request_id INT NOT NULL,
    actor_borrowernumber INT NOT NULL,
    event_kind VARCHAR(32) NOT NULL,
    from_location VARCHAR(200) NULL,
    to_location VARCHAR(200) NULL,
    from_starts_at DATETIME NULL,
    to_starts_at DATETIME NULL,
    from_due_date DATETIME NULL,
    to_due_date DATETIME NULL,
    note VARCHAR(1000) NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ls_handoff_request (request_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_request_messages (
    id INT NOT NULL AUTO_INCREMENT,
    request_id INT NOT NULL,
    sender_borrowernumber INT NOT NULL,
    message TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ls_message_request (request_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_wanted_items (
    id INT NOT NULL AUTO_INCREMENT,
    patron_borrowernumber INT NOT NULL,
    title VARCHAR(200) NOT NULL,
    category VARCHAR(80) NOT NULL DEFAULT '',
    description VARCHAR(1000) NOT NULL DEFAULT '',
    status ENUM('open','fulfilled','closed') NOT NULL DEFAULT 'open',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ls_wanted_status (status, created_at),
    KEY ls_wanted_patron (patron_borrowernumber, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_wanted_interests (
    wanted_id INT NOT NULL,
    patron_borrowernumber INT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (wanted_id, patron_borrowernumber)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_reviews (
    id INT NOT NULL AUTO_INCREMENT,
    request_id INT NOT NULL,
    reviewer_borrowernumber INT NOT NULL,
    reviewee_borrowernumber INT NOT NULL,
    rating TINYINT NOT NULL,
    body VARCHAR(1000) NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY ls_review_once (request_id, reviewer_borrowernumber),
    KEY ls_reviewee (reviewee_borrowernumber, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_notifications (
    id INT NOT NULL AUTO_INCREMENT,
    patron_borrowernumber INT NOT NULL,
    kind VARCHAR(40) NOT NULL,
    title VARCHAR(200) NOT NULL,
    body VARCHAR(1000) NOT NULL DEFAULT '',
    link VARCHAR(255) NOT NULL DEFAULT '',
    dedupe_key VARCHAR(190) NULL,
    read_at DATETIME NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY ls_notification_dedupe (dedupe_key),
    KEY ls_notification_patron (patron_borrowernumber, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_patron_stats (
    borrowernumber INT NOT NULL,
    loans_as_lender INT NOT NULL DEFAULT 0,
    loans_as_borrower INT NOT NULL DEFAULT 0,
    distinct_items_lent INT NOT NULL DEFAULT 0,
    est_value_saved DECIMAL(18,2) NOT NULL DEFAULT 0,
    est_co2_kg DECIMAL(10,2) NOT NULL DEFAULT 0,
    level INT NOT NULL DEFAULT 1,
    share_credits INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (borrowernumber)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_share_credits_ledger (
    id INT NOT NULL AUTO_INCREMENT,
    patron_borrowernumber INT NOT NULL,
    delta INT NOT NULL,
    reason VARCHAR(40) NOT NULL,
    related_request_id INT NULL,
    related_listing_id INT NULL,
    note VARCHAR(500) NOT NULL DEFAULT '',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ls_credit_patron (patron_borrowernumber, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_badges (
    id INT NOT NULL AUTO_INCREMENT,
    borrowernumber INT NOT NULL,
    badge_key VARCHAR(80) NOT NULL,
    earned_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY ls_badge_unique (borrowernumber, badge_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_challenges (
    id INT NOT NULL AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    description VARCHAR(1000) NOT NULL DEFAULT '',
    goal INT NOT NULL DEFAULT 1,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ls_challenge_dates (active, start_date, end_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_challenge_progress (
    challenge_id INT NOT NULL,
    borrowernumber INT NOT NULL,
    progress INT NOT NULL DEFAULT 0,
    completed_at DATETIME NULL,
    PRIMARY KEY (challenge_id, borrowernumber)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_kudos (
    id INT NOT NULL AUTO_INCREMENT,
    request_id INT NOT NULL,
    sender_borrowernumber INT NOT NULL,
    recipient_borrowernumber INT NOT NULL,
    message VARCHAR(500) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY ls_kudos_request_sender (request_id, sender_borrowernumber),
    KEY ls_kudos_recipient (recipient_borrowernumber, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_settings (
    setting_key VARCHAR(100) NOT NULL,
    setting_value TEXT NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (setting_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS koha_plugin_com_libraryshare_legal_acceptances (
    borrowernumber INT NOT NULL,
    document_key VARCHAR(80) NOT NULL,
    document_version VARCHAR(40) NOT NULL,
    accepted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (borrowernumber, document_key, document_version)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
