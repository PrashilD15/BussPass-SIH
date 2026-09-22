import json

en_adds = {
  "home": {
    "greeting_morning": "Good morning,",
    "greeting_afternoon": "Good afternoon,",
    "greeting_evening": "Good evening,",
    "search_title": "Where to?",
    "search_subtitle": "Search stops, routes, or cities",
    "quick_actions": "Quick Actions",
    "live_map": "Live Map",
    "timetables": "Timetables",
    "buy_pass": "Buy Pass",
    "my_passes": "My Passes",
    "your_journeys": "Your Journeys",
    "select_language": "Select Language"
  }
}

mr_adds = {
  "home": {
    "greeting_morning": "शुभ सकाळ,",
    "greeting_afternoon": "शुभ दुपार,",
    "greeting_evening": "शुभ संध्याकाळ,",
    "search_title": "कुठे जायचे आहे?",
    "search_subtitle": "थांबे, मार्ग किंवा शहरे शोधा",
    "quick_actions": "जलद कृती",
    "live_map": "थेट नकाशा",
    "timetables": "वेळापत्रक",
    "buy_pass": "पास खरेदी करा",
    "my_passes": "माझे पास",
    "your_journeys": "तुमचे प्रवास",
    "select_language": "भाषा निवडा"
  }
}

hi_adds = {
  "home": {
    "greeting_morning": "सुप्रभात,",
    "greeting_afternoon": "शुभ दोपहर,",
    "greeting_evening": "शुभ संध्या,",
    "search_title": "कहाँ जाना है?",
    "search_subtitle": "स्टॉप, रूट या शहर खोजें",
    "quick_actions": "त्वरित क्रियाएँ",
    "live_map": "लाइव मैप",
    "timetables": "समय सारिणी",
    "buy_pass": "पास खरीदें",
    "my_passes": "मेरे पास",
    "your_journeys": "आपकी यात्रा",
    "select_language": "भाषा चुनें"
  }
}

kn_adds = {
  "home": {
    "greeting_morning": "ಶುಭೋದಯ,",
    "greeting_afternoon": "ಶುಭ ಮಧ್ಯಾಹ್ನ,",
    "greeting_evening": "ಶುಭ ಸಂಜೆ,",
    "search_title": "ಎಲ್ಲಿಗೆ ಹೋಗಬೇಕು?",
    "search_subtitle": "ನಿಲ್ದಾಣಗಳು, ಮಾರ್ಗಗಳು ಅಥವಾ ನಗರಗಳನ್ನು ಹುಡುಕಿ",
    "quick_actions": "ತ್ವರಿತ ಕ್ರಿಯೆಗಳು",
    "live_map": "ಲೈವ್ ನಕ್ಷೆ",
    "timetables": "ವೇಳಾಪಟ್ಟಿ",
    "buy_pass": "ಪಾಸ್ ಖರೀದಿಸಿ",
    "my_passes": "ನನ್ನ ಪಾಸ್‌ಗಳು",
    "your_journeys": "ನಿಮ್ಮ ಪ್ರಯಾಣಗಳು",
    "select_language": "ಭಾಷೆಯನ್ನು ಆಯ್ಕೆಮಾಡಿ"
  }
}

for lang, adds in [('en', en_adds), ('mr', mr_adds), ('hi', hi_adds), ('kn', kn_adds)]:
    with open(f'assets/translations/{lang}.json', 'r') as f:
        data = json.load(f)
    data.update(adds)
    with open(f'assets/translations/{lang}.json', 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

print("Updated translation files.")
