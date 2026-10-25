import 'package:flutter/material.dart';

const List<String> kStages = [
  'Inquiry',
  'Negotiation',
  'Contract',
  'Production',
  'Review',
  'Live',
  'Performance',
  'Payment',
  'Closed',
];
const String kCancelled = 'Cancelled';
const List<String> kAllStages = [...kStages, kCancelled];

bool isActiveStage(String s) => s != 'Closed' && s != kCancelled;
int stageIndex(String s) => kStages.indexOf(s);

const List<String> kDealTypes = ['Paid', 'Barter', 'Hybrid'];
const List<String> kSources = ['Email', 'Instagram DM', 'Agency', 'WhatsApp', 'Referral', 'Other'];
const List<String> kDeliverableTypes = ['Reel', 'Story', 'Post', 'Carousel', 'YouTube video', 'Short', 'Live session', 'Other'];
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

const Color kPrimary = Color(0xFF3550D8);
const Color kOk = Color(0xFF127A52);
const Color kWarn = Color(0xFFB54708);
const Color kDanger = Color(0xFFB42318);
const Color kMuted = Color(0xFF5B616E);
const Color kBg = Color(0xFFF3F4F6);

Color stageColor(String s) {
  switch (s) {
    case 'Inquiry':
    case 'Negotiation':
    case 'Contract':
      return kPrimary;
    case 'Production':
    case 'Review':
      return kWarn;
    case 'Live':
    case 'Performance':
    case 'Payment':
      return kOk;
    case kCancelled:
      return kDanger;
    default:
      return const Color(0xFF3A3F4A);
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
