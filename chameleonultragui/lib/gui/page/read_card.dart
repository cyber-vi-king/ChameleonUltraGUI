import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/gui/component/card_recovery.dart';
import 'package:chameleonultragui/gui/component/error_message.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/recovery.dart';
import 'package:chameleonultragui/main.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:chameleonultragui/connector/serial_abstract.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

enum MifareClassicState {
  none,
  checkKeys,
  checkKeysOngoing,
  recovery,
  recoveryOngoing,
  dump,
  dumpOngoing,
  save
}

// cardExist true because we don't show error to user if nothing is done
class HFCardInfo {
  String uid;
  String sak;
  String atqa;
  String tech;
  String ats;
  bool cardExist;

  HFCardInfo(
      {this.uid = '',
      this.sak = '',
      this.atqa = '',
      this.tech = '',
      this.ats = '',
      this.cardExist = true});
}

class LFCardInfo {
  String uid;
  String tech;
  bool cardExist;

  LFCardInfo({this.uid = '', this.tech = '', this.cardExist = true});
}

class MifareClassicInfo {
  bool isEV1;
  MifareClassicRecovery? recovery;
  MifareClassicType type;
  MifareClassicState state;

  MifareClassicInfo(
      {MifareClassicRecovery? recovery,
      this.isEV1 = false,
      this.type = MifareClassicType.none,
      this.state = MifareClassicState.none});
}

class ReadCardPage extends StatefulWidget {
  const ReadCardPage({super.key});

  @override
  ReadCardPageState createState() => ReadCardPageState();
}

class ReadCardPageState extends State<ReadCardPage> {
  String dumpName = "";
  HFCardInfo hfInfo = HFCardInfo();
  LFCardInfo lfInfo = LFCardInfo();
  MifareClassicInfo mfcInfo = MifareClassicInfo();

  void updateMifareClassicRecovery() {
    setState(() {
      mfcInfo.recovery = mfcInfo.recovery;
    });
  }

  void updateMifareClassicInfo() {
    setState(() {
      mfcInfo = mfcInfo;
    });
  }

  Future<void> readHFInfo() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;

    setState(() {
      hfInfo = HFCardInfo();
      mfcInfo = MifareClassicInfo();
    });

    try {
      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      CardData card = await appState.communicator!.scan14443aTag();
      bool isMifareClassic = false;

      try {
        isMifareClassic = await appState.communicator!.detectMf1Support();
      } catch (_) {}

      bool isMifareClassicEV1 = isMifareClassic
          ? (await appState.communicator!
              .mf1Auth(0x45, 0x61, gMifareClassicKeys[3]))
          : false;

      if (isMifareClassic) {
        MifareClassicRecovery recovery = MifareClassicRecovery(
            update: updateMifareClassicRecovery, appState: appState);

        setState(() {
          mfcInfo.recovery = recovery;
        });
      }

      setState(() {
        hfInfo.uid = bytesToHexSpace(card.uid);
        hfInfo.sak = card.sak.toRadixString(16).padLeft(2, '0').toUpperCase();
        hfInfo.atqa = bytesToHexSpace(card.atqa);
        hfInfo.ats = (card.ats.isNotEmpty)
            ? bytesToHexSpace(card.ats)
            : localizations.no;
        mfcInfo.isEV1 = isMifareClassicEV1;
        mfcInfo.type = isMifareClassic
            ? mfClassicGetType(card.atqa, card.sak)
            : MifareClassicType.none;
        mfcInfo.state = (mfcInfo.type != MifareClassicType.none)
            ? MifareClassicState.checkKeys
            : MifareClassicState.none;
        hfInfo.tech = isMifareClassic
            ? "Mifare Classic ${mfClassicGetName(mfcInfo.type)}${isMifareClassicEV1 ? " EV1" : ""}"
            : localizations.other;
      });
    } catch (_) {
      setState(() {
        hfInfo.cardExist = false;
      });
    }
  }

  Future<void> readLFInfo() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    try {
      setState(() {
        lfInfo = LFCardInfo();
      });

      if (!await appState.communicator!.isReaderDeviceMode()) {
        await appState.communicator!.setReaderDeviceMode(true);
      }

      var card = await appState.communicator!.readEM410X();
      if (card != "") {
        setState(() {
          lfInfo.uid = card;
          lfInfo.tech = "EM-Marin EM4100/EM4102";
        });
      } else {
        setState(() {
          lfInfo.cardExist = false;
        });
      }
    } catch (_) {}
  }

  Future<void> saveHFCard() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);
    var localizations = AppLocalizations.of(context)!;

    var tags = appState.sharedPreferencesProvider.getCards();
    tags.add(CardSave(
        uid: hfInfo.uid,
        sak: hexToBytes(hfInfo.sak)[0],
        atqa: hexToBytesSpace(hfInfo.atqa),
        name: dumpName,
        tag: TagType.mifare1K,
        data: [],
        ats: (hfInfo.ats != localizations.no)
            ? hexToBytesSpace(hfInfo.ats)
            : Uint8List(0)));

    appState.sharedPreferencesProvider.setCards(tags);
  }

  Future<void> saveLFCard() async {
    var appState = Provider.of<ChameleonGUIState>(context, listen: false);

    var tags = appState.sharedPreferencesProvider.getCards();
    tags.add(CardSave(uid: lfInfo.uid, name: dumpName, tag: TagType.em410X));
    appState.sharedPreferencesProvider.setCards(tags);
  }

  Widget buildFieldRow(String label, String value, double fontSize) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        '$label: $value',
        textAlign: (MediaQuery.of(context).size.width < 800)
            ? TextAlign.left
            : TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    var localizations = AppLocalizations.of(context)!;
    final isSmallScreen = screenSize.width < 800;

    double fieldFontSize = isSmallScreen ? 16 : 20;

    var appState = context.watch<ChameleonGUIState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(localizations.read_card),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Center(
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        localizations.hf_tag_info,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildFieldRow(
                          localizations.uid, hfInfo.uid, fieldFontSize),
                      buildFieldRow(
                          localizations.sak, hfInfo.sak, fieldFontSize),
                      buildFieldRow(
                          localizations.atqa, hfInfo.atqa, fieldFontSize),
                      buildFieldRow(
                          localizations.ats, hfInfo.ats, fieldFontSize),
                      const SizedBox(height: 16),
                      Text(
                        '${localizations.card_tech}: ${hfInfo.tech}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: fieldFontSize),
                      ),
                      const SizedBox(height: 16),
                      if (!hfInfo.cardExist) ...[
                        ErrorMessage(errorMessage: localizations.no_card_found),
                        const SizedBox(height: 16)
                      ],
                      ElevatedButton(
                        onPressed: () async {
                          if (appState.connector!.device ==
                              ChameleonDevice.ultra) {
                            await readHFInfo();
                          } else if (appState.connector!.device ==
                              ChameleonDevice.lite) {
                            showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => AlertDialog(
                                title: Text(localizations.no_supported),
                                content: Text(localizations.lite_no_read,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () => Navigator.pop(
                                        context, localizations.ok),
                                    child: Text(localizations.ok),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            appState.changesMade();
                          }
                        },
                        child: Text(localizations.read),
                      ),
                      if (hfInfo.uid != "") ...[
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(localizations.enter_name_of_card),
                                  content: TextField(
                                    onChanged: (value) {
                                      setState(() {
                                        dumpName = value;
                                      });
                                    },
                                  ),
                                  actions: [
                                    ElevatedButton(
                                      onPressed: () async {
                                        await saveHFCard();
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                                      child: Text(localizations.ok),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(
                                            context); // Close the modal without saving
                                      },
                                      child: Text(localizations.cancel),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          child: Text(localizations.save_only_uid),
                        ),
                      ],
                      if (mfcInfo.type != MifareClassicType.none)
                        CardRecovery(mfcInfo: mfcInfo, hfInfo: hfInfo)
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        localizations.lf_tag_info,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildFieldRow(
                          localizations.uid, lfInfo.uid, fieldFontSize),
                      const SizedBox(height: 16),
                      Text(
                        '${localizations.card_tech}: ${lfInfo.tech}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: fieldFontSize),
                      ),
                      const SizedBox(height: 16),
                      if (!lfInfo.cardExist) ...[
                        ErrorMessage(errorMessage: localizations.no_card_found),
                        const SizedBox(height: 16)
                      ],
                      ElevatedButton(
                        onPressed: () async {
                          if (appState.connector!.device ==
                              ChameleonDevice.ultra) {
                            await readLFInfo();
                          } else if (appState.connector!.device ==
                              ChameleonDevice.lite) {
                            showDialog<String>(
                              context: context,
                              builder: (BuildContext context) => AlertDialog(
                                title: Text(localizations.no_supported),
                                content: Text(localizations.lite_no_read,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                actions: <Widget>[
                                  TextButton(
                                    onPressed: () => Navigator.pop(
                                        context, localizations.ok),
                                    child: Text(localizations.ok),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            appState.changesMade();
                          }
                        },
                        child: Text(localizations.read),
                      ),
                      if (lfInfo.uid != "") ...[
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () async {
                            await showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text(localizations.enter_name_of_card),
                                  content: TextField(
                                    onChanged: (value) {
                                      setState(() {
                                        dumpName = value;
                                      });
                                    },
                                  ),
                                  actions: [
                                    ElevatedButton(
                                      onPressed: () async {
                                        await saveLFCard();
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                        }
                                      },
                                      child: Text(localizations.ok),
                                    ),
                                    ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(
                                            context); // Close the modal without saving
                                      },
                                      child: Text(localizations.cancel),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          child: Text(localizations.save),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
