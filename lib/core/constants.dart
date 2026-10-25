import 'package:flutter/material.dart';

/// Simple creator lifecycle (v2).
const List<String> kStages = ['Talking', 'Confirmed', 'Shooting', 'Posted', 'Done'];
const String kCancelled = 'Cancelled';
const List<String> kAllStages = [...kStages, kCancelled];

const Map<String, String> kStageHint = {
  'Talking': 'Inquiry or negotiating',
  'Confirmed': 'Deal agreed',
  'Shooting': 'Creating content',
  'Posted': 'Content is live',
  'Done': 'Paid / complete',
};

bool isActiveStage(String s) => s != 'Done' && s != kCancelled;
int stageIndex(String s) => kStages.indexOf(s);

/// Maps v1 stages to v2 (used by the DB migration).
const Map<String, String> kStageMigration = {
  'Inquiry': 'Talking',
  'Negotiation': 'Talking',
  'Contract': 'Confirmed',
  'Production': 'Shooting',
  'Review': 'Shooting',
  'Live': 'Posted',
  'Performance': 'Posted',
  'Payment': 'Posted',
  'Closed': 'Done',
};

const String kPaid = 'Paid';
const String kBarter = 'Barter';
const String kBoth = 'Barter + Paid';
const List<String> kDealTypes = [kBarter, kPaid, kBoth];

const List<String> kSources = ['Email', 'Instagram DM', 'Agency', 'WhatsApp', 'Referral', 'Other'];
const List<String> kDeliverableTypes = ['Reel', 'Story', 'Post', 'Carousel', 'YouTube video', 'Short', 'Live session', 'Other'];
const List<String> kQuickDeliverables = ['Reel', 'Story', 'Post', 'YouTube video'];
const List<String> kPlatforms = ['Instagram', 'YouTube', 'Facebook', 'LinkedIn', 'X', 'Snapchat', 'Other'];
const List<String> kDeliverableStatuses = ['Planned', 'Scripting', 'Shot', 'Draft sent', 'Revision', 'Approved', 'Live'];
const List<String> kChecklist = [
  '#ad / Paid partnership label',
  'Brand handle tagged',
  'Discount code / link in caption',
  'Mandatory hashtags from brief',
  'Kept live for full rights window',
];
const List<String> kSnapshotLabels = ['24h', '7d', '30d', 'Custom'];
const List<String> kExpenseCategories = ['Editor', 'Props', 'Travel', 'Agency commission', 'Equipment', 'Other'];
const List<String> kPaymentMethods = ['Bank transfer', 'UPI', 'Cheque', 'Cash', 'Other'];
const List<String> kLinkTypes = ['Shopping', 'Brand website', 'Affiliate', 'Demo video', 'Social media', 'Other'];

// ---- v2 palette ----
const Color kPrimary = Color(0xFF5B3FD6); // cash / app accent (violet)
const Color kPrimaryTint = Color(0xFFECE8FC);
const Color kBarterC = Color(0xFFC2306A); // barter (pink)
const Color kBarterTint = Color(0xFFFDE8EF);
const Color kBarterBar = Color(0xFFE8628F);
const Color kBothC = Color(0xFF0B6B45);
const Color kBothTint = Color(0xFFE5F6EE);
const Color kInk = Color(0xFF17142B);
const Color kOk = Color(0xFF0E9F63);
const Color kWarn = Color(0xFFB54708);
const Color kWarnTint = Color(0xFFFFF1E5);
const Color kDanger = Color(0xFFB42318);
const Color kMuted = Color(0xFF5E5A75);
const Color kLine = Color(0xFFECEAF4);
const Color kBg = Color(0xFFF6F5FB);

Color typeColor(String t) => t == kBarter ? kBarterC : (t == kBoth ? kBothC : kPrimary);
Color typeTint(String t) => t == kBarter ? kBarterTint : (t == kBoth ? kBothTint : kPrimaryTint);

Color stageColor(String s) {
  switch (s) {
    case 'Talking':
      return kPrimary;
    case 'Confirmed':
      return const Color(0xFF3F2A9E);
    case 'Shooting':
      return const Color(0xFFE59A1A);
    case 'Posted':
    case 'Done':
      return kOk;
    case kCancelled:
      return kDanger;
    default:
      return kMuted;
  }
}

Color deliverableStatusColor(String s) {
  switch (s) {
    case 'Live':
      return kOk;
    case 'Approved':
      return kPrimary;
    case 'Revision':
    case 'Draft sent':
      return kWarn;
    default:
      return kMuted;
  }
}

const int kLimitMin = 1;
const int kLimitMax = 100;
