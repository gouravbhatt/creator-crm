import 'package:flutter/material.dart';

const String kAppName = 'Collabook';
const String kTagline = 'Every collab. Every rupee.';

/// Creator lifecycle (v3). 'Done' is shown as "Paid / done".
const List<String> kStages = ['Lead', 'Confirmed', 'Creating', 'Posted', 'Done'];
const String kCancelled = 'Cancelled';
const List<String> kAllStages = [...kStages, kCancelled];

const Map<String, String> kStageLabel = {
  'Lead': 'Lead',
  'Confirmed': 'Confirmed',
  'Creating': 'Creating',
  'Posted': 'Posted',
  'Done': 'Paid',
  kCancelled: 'Cancelled',
};

const Map<String, String> kStageHint = {
  'Lead': 'Talking / negotiating',
  'Confirmed': 'Deal agreed',
  'Creating': 'Shooting / drafts',
  'Posted': 'Content is live or delivered',
  'Done': 'Paid and complete',
};

String stageLabel(String s) => kStageLabel[s] ?? s;
bool isActiveStage(String s) => s != 'Done' && s != kCancelled;
int stageIndex(String s) => kStages.indexOf(s);

/// Maps older stage names to v3 (used by the DB migration and old backups).
const Map<String, String> kStageMigration = {
  'Inquiry': 'Lead',
  'Negotiation': 'Lead',
  'Talking': 'Lead',
  'Contract': 'Confirmed',
  'Production': 'Creating',
  'Review': 'Creating',
  'Shooting': 'Creating',
  'Live': 'Posted',
  'Performance': 'Posted',
  'Payment': 'Posted',
  'Closed': 'Done',
};

// ---- collab kinds ----
const String kPaid = 'Paid';
const String kBarter = 'Barter';
const String kBoth = 'Paid + Barter';
const String kOrder = 'Order & refund';
const String kUgc = 'UGC';
const String kCommission = 'Commission';
const String kGifting = 'Gifting / PR';
const String kEvent = 'Event';
const List<String> kDealTypes = [kPaid, kBarter, kBoth, kOrder, kUgc, kCommission, kGifting, kEvent];

/// Older names → v3 kinds.
const Map<String, String> kKindMigration = {'Barter + Paid': kBoth, 'Hybrid': kBoth};

const Map<String, String> kKindHint = {
  kPaid: 'Cash fee for content',
  kBarter: 'Brand sends product',
  kBoth: 'Product + cash fee',
  kOrder: 'I buy, brand refunds',
  kUgc: 'Video for brand’s ads',
  kCommission: 'Code / link, paid per sale',
  kGifting: 'Gift, no fixed deliverable',
  kEvent: 'Launch, meet-up, shoot day',
};

const Map<String, String> kKindIcon = {
  kPaid: '₹',
  kBarter: '◆',
  kBoth: '✦',
  kOrder: '↺',
  kUgc: '▶',
  kCommission: '%',
  kGifting: '✉',
  kEvent: '★',
};

/// Kinds where a product is part of the deal by default.
bool kindHasProduct(String k) => k == kBarter || k == kBoth || k == kOrder || k == kGifting;

/// Kinds that always carry a cash fee.
bool kindHasFee(String k) => k == kPaid || k == kBoth || k == kUgc || k == kEvent;

// Fee modes for Order & refund.
const String kFeeNone = 'none';
const String kFeeTop = 'top';
const String kFeeIncl = 'incl';

const List<String> kSources = ['Instagram DM', 'Email', 'WhatsApp', 'Agency', 'Platform app', 'Manager', 'Referral', 'I pitched', 'Other'];
bool sourceHasAgency(String? s) => s == 'Agency' || s == 'Platform app' || s == 'Manager';

const List<String> kPaymentKinds = ['Fee', 'Refund', 'Fee + Refund', 'Advance', 'Kill fee'];

const List<String> kAddons = ['Usage rights', 'Ad rights (paid ads)', 'Whitelisting', 'Raw files', 'Exclusivity'];

const List<String> kAffiliatePlatforms = [
  'Amazon Associates', 'Flipkart Affiliate', 'Wishlink', 'LehLah', 'EarnKaro', 'Myntra', 'Ajio', 'Meesho', 'Other'
];
const List<String> kOtherIncomeTypes = ['YouTube AdSense', 'Instagram bonus', 'Course / digital', 'Event / talk', 'Other'];
const List<String> kIncomeStatuses = ['Pending', 'Confirmed', 'Paid'];

const List<String> kDeliverableTypes = ['Reel', 'Story', 'Post', 'Carousel', 'YouTube video', 'Short', 'UGC video', 'Raw footage', 'Live session', 'Other'];
const List<String> kPlatforms = ['Instagram', 'YouTube', 'Facebook', 'LinkedIn', 'X', 'Snapchat', 'Brand (UGC)', 'Other'];
const List<String> kDeliverableStatuses = ['Planned', 'Scripting', 'Shot', 'Draft sent', 'Revision', 'Approved', 'Live'];
bool isUgcDeliverable(Map<String, dynamic> d) => d['type'] == 'UGC video' || d['type'] == 'Raw footage' || d['platform'] == 'Brand (UGC)';
String deliverableStatusLabel(Map<String, dynamic> d) {
  final s = (d['status'] ?? '').toString();
  if (s == 'Live') return isUgcDeliverable(d) ? 'Delivered' : 'Posted';
  return s;
}

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

// ---- palette: colour = meaning ----
const Color kInk = Color(0xFF17142B);
const Color kPrimary = Color(0xFF5B3FD6); // brand · cash fee
const Color kPrimaryDark = Color(0xFF3F2A9E);
const Color kPrimaryTint = Color(0xFFECE8FC);
const Color kBarterC = Color(0xFFC2306A); // barter / products
const Color kBarterDark = Color(0xFFA3194E);
const Color kBarterTint = Color(0xFFFDE8EF);
const Color kBarterBar = Color(0xFFE8628F);
const Color kMint = Color(0xFF0E9F63); // affiliate · paid · done
const Color kMintDark = Color(0xFF0B6B45);
const Color kMintTint = Color(0xFFE5F6EE);
const Color kAmber = Color(0xFFB54708); // refund due · due soon
const Color kAmberDark = Color(0xFF8A3A06);
const Color kAmberTint = Color(0xFFFFF1E5);
const Color kBlue = Color(0xFF1D4FB0); // UGC
const Color kBlueTint = Color(0xFFE4EDFC);
const Color kDanger = Color(0xFFB42318); // overdue only
const Color kDangerTint = Color(0xFFFCEBEA);
const Color kMuted = Color(0xFF5E5A75);
const Color kBody = Color(0xFF3B3753);
const Color kLine = Color(0xFFECEAF4);
const Color kBg = Color(0xFFF6F5FB);

// legacy aliases
const Color kOk = kMint;
const Color kWarn = kAmber;
const Color kWarnTint = kAmberTint;
const Color kBothC = kMintDark;
const Color kBothTint = kMintTint;

Color typeColor(String t) {
  switch (t) {
    case kBarter:
    case kGifting:
      return kBarterDark;
    case kBoth:
    case kCommission:
      return kMintDark;
    case kOrder:
      return kAmberDark;
    case kUgc:
      return kBlue;
    default:
      return kPrimaryDark;
  }
}

Color typeTint(String t) {
  switch (t) {
    case kBarter:
    case kGifting:
      return kBarterTint;
    case kBoth:
    case kCommission:
      return kMintTint;
    case kOrder:
      return kAmberTint;
    case kUgc:
      return kBlueTint;
    default:
      return kPrimaryTint;
  }
}

Color stageColor(String s) {
  switch (s) {
    case 'Lead':
      return kMuted;
    case 'Confirmed':
      return kPrimaryDark;
    case 'Creating':
      return kAmber;
    case 'Posted':
      return kPrimary;
    case 'Done':
      return kMint;
    case kCancelled:
      return kDanger;
    default:
      return kMuted;
  }
}

Color deliverableStatusColor(String s) {
  switch (s) {
    case 'Live':
      return kMintDark;
    case 'Approved':
      return kPrimaryDark;
    case 'Revision':
    case 'Draft sent':
      return kAmberDark;
    default:
      return kBody;
  }
}

const int kLimitMin = 1;
const int kLimitMax = 100;
