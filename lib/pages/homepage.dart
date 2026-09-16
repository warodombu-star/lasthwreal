import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/billing_record_model.dart';
import '../services/database_helper.dart';
import 'billing_entry.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.title});

  final String title;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<BillingRecordModel> billingItems = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Center(
          child: Text(widget.title, style: TextStyle(fontSize: 18)),
        ),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),

      body: StreamBuilder(
        stream: DatabaseHelper().getStreamBillingRecords(),
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.docs.isEmpty) {
            return Center(child: Text('No billing records found.'));
          }
          return _buildListView(snapshot);
        },
      ),
      bottomNavigationBar: BottomAppBar(
        shape: CircularNotchedRectangle(),
        child: Padding(padding: const EdgeInsets.all(12.0)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.deepPurple,
        shape: CircleBorder(),
        tooltip: 'Add Electricity Payment Entry',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BillingEntry(
                action: 'add',
                billingRecord: BillingRecordModel(
                  userId: 'U001',
                  month: DateFormat('MMMM yyyy').format(DateTime.now()),
                  units: 0,
                  amount: 0.0,
                  paidStatus: 'Paid',
                ),
              ),
            ),
          );
        },
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // Build the ListView for displaying billing records
  Widget _buildListView(AsyncSnapshot snapshot) {
    billingItems.clear();
    for (var doc in snapshot.data!.docs) {
      billingItems.add(
        BillingRecordModel(
          userId: doc.get('userId'),
          month: doc.get('month'),
          units: doc.get('units') as int,
          amount: doc.get('amount') is int
              ? (doc.get('amount') as int).toDouble()
              : doc.get('amount') as double,
          paidStatus: doc.get('paidStatus'),
          referenceId: doc.id,
        ),
      ); // Update the snapshot data with the model
    }
    // Sort the billing items by month
    billingItems.sort((a, b) {
      // ใช้ DateFormat จากแพ็กเกจ intl เพื่อแปลง String เป็น DateTime
      DateFormat format = DateFormat("MMMM yyyy");

      DateTime dateA = format.parse(a.month);
      DateTime dateB = format.parse(b.month);

      return dateA.compareTo(dateB);
    });

    return ListView.separated(
      itemCount: billingItems.length,
      itemBuilder: (BuildContext context, int index) {
        final item = billingItems[index];
        String titleDate = item.month;
        String paidStatusText = item.paidStatus == 'Paid'
            ? 'ชำระแล้ว'
            : 'ยังไม่ชำระ';
        String subtitle =
            "หน่วยที่ใช้ ${item.units} หน่วย, ${item.amount} บาท\n$paidStatusText";

        // Dismissible ครอบ ListTile เพื่อให้รองรับ Swipe 2 ทิศทาง
        // - Swipe จากขวาไปซ้าย (endToStart) => ลบข้อมูล (ต้องยืนยัน Yes/No ก่อน)
        // - Swipe จากซ้ายไปขวา (startToEnd) => แก้ไขข้อมูล
        return Dismissible(
          key: ValueKey(item.referenceId),
          direction: DismissDirection.horizontal,
          // พื้นหลังตอน swipe จากซ้ายไปขวา (แสดงไอคอนแก้ไข)
          background: Container(
            color: Colors.blue,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.edit, color: Colors.white),
          ),
          // พื้นหลังตอน swipe จากขวาไปซ้าย (แสดงไอคอนลบ)
          secondaryBackground: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.endToStart) {
              // Swipe ขวา -> ซ้าย : ลบข้อมูล ต้องยืนยันก่อนทุกครั้ง
              final bool? confirm = await _showDeleteConfirmDialog(context);
              if (confirm == true) {
                try {
                  await DatabaseHelper().deleteBillingRecord(
                    item.referenceId!,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('ลบข้อมูลเรียบร้อยแล้ว'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                  // คืนค่า true เพื่อให้ Dismissible เอา item ออกจาก Widget list
                  // (รายการจริงบน Home จะอัปเดตอัตโนมัติผ่าน StreamBuilder อยู่แล้ว)
                  return true;
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('ลบข้อมูลไม่สำเร็จ: $error'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                  return false;
                }
              }
              // กด No หรือปิด dialog => ไม่ลบ
              return false;
            } else {
              // Swipe ซ้าย -> ขวา : แก้ไขข้อมูล
              // ไปหน้าฟอร์มแก้ไข พร้อมส่งค่าเดิมของรายการที่เลือกไปแสดง
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BillingEntry(
                    action: 'edit',
                    billingRecord: BillingRecordModel(
                      userId: item.userId,
                      month: item.month,
                      units: item.units,
                      amount: item.amount,
                      paidStatus: item.paidStatus,
                      referenceId: item.referenceId,
                    ),
                  ),
                ),
              );
              // ไม่ต้องการให้ item หายไปจาก list เพียงแค่เปิดฟอร์มแก้ไข
              return false;
            }
          },
          child: ListTile(
            title: Text(
              titleDate,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(subtitle, style: TextStyle(fontSize: 14)),
            onTap: () {},
          ),
        );
      },
      separatorBuilder: (BuildContext context, int index) {
        return Divider(color: Colors.grey);
      },
    );
  }

  // Dialog ยืนยันก่อนลบข้อมูล (Yes/No)
  Future<bool?> _showDeleteConfirmDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('ยืนยันการลบข้อมูล'),
          content: const Text('คุณต้องการลบรายการนี้ใช่หรือไม่?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }
}
