import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:secure_vault/services/wallet_service.dart';
import 'package:secure_vault/services/filebase_service.dart';

class StorageSummaryCard extends StatefulWidget {
  const StorageSummaryCard({super.key});

  @override
  State<StorageSummaryCard> createState() => _StorageSummaryCardState();
}

class _StorageSummaryCardState extends State<StorageSummaryCard> 
    with AutomaticKeepAliveClientMixin {
  
  String _walletAddress = '';
  String _networkName = 'Ethereum';
  bool _isConnected = false;
  int _filesStored = 0;
  double _storageUsed = 0.0;
  bool _hasLoadedOnce = false;
  Map<String, dynamic> _fileTypeStats = {}; // ADD FILE TYPE STATS

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    try {
      final data = await SessionWalletService.getSessionWalletData();
      
      if (mounted) {
        setState(() {
          _walletAddress = data['address'] ?? '';
          _networkName = data['network'] ?? 'Ethereum';
          _isConnected = data['isConnected'] ?? false;
        });
        
        if (_walletAddress.isNotEmpty) {
          await _loadRealStorageData();
        } else {
          setState(() {
            _filesStored = 0;
            _storageUsed = 0.0;
            _fileTypeStats = {};
            _hasLoadedOnce = true;
          });
        }
      }
    } catch (e) {
      print('Error loading session data: $e');
      if (mounted) {
        setState(() {
          _hasLoadedOnce = true;
        });
      }
    }
  }

  // ENHANCED: Load storage data with file type breakdown
  Future<void> _loadRealStorageData() async {
    try {
      print('🔍 Loading storage data for wallet: $_walletAddress');
      
      // Try cache first for instant display
      final cachedStats = FilebaseService.getCachedStats(_walletAddress);
      if (cachedStats != null && mounted) {
        setState(() {
          _filesStored = cachedStats['totalFiles'] ?? 0;
          _storageUsed = (cachedStats['totalSize'] ?? 0) / (1024 * 1024);
          _fileTypeStats = _calculateFileTypeStats(cachedStats);
          _hasLoadedOnce = true;
        });
        print('📦 Using cached stats: $_filesStored files, ${_storageUsed.toStringAsFixed(2)} MB');
      }
      
      // Then get fresh data
      final stats = await FilebaseService.getStorageStats(_walletAddress);
      final files = await FilebaseService.getUserFilesWithSync(_walletAddress);
      print('📊 Storage stats received: $stats');
      
      if (mounted) {
        setState(() {
          _filesStored = stats['totalFiles'] ?? 0;
          _storageUsed = (stats['totalSize'] ?? 0) / (1024 * 1024);
          _fileTypeStats = _calculateFileTypeStatsFromFiles(files);
          _hasLoadedOnce = true;
        });
        print('✅ Storage data updated: $_filesStored files, ${_storageUsed.toStringAsFixed(2)} MB');
      }
    } catch (e) {
      print('❌ Error loading storage data: $e');
      if (mounted) {
        setState(() {
          _filesStored = 0;
          _storageUsed = 0.0;
          _fileTypeStats = {};
          _hasLoadedOnce = true;
        });
      }
    }
  }

  // NEW: Calculate file type statistics from cached stats
  Map<String, dynamic> _calculateFileTypeStats(Map<String, dynamic> stats) {
    // This is a fallback for cached data
    return {
      'types': <String, Map<String, dynamic>>{},
      'totalSize': stats['totalSize'] ?? 0,
    };
  }

  // NEW: Calculate detailed file type statistics from files
// UPDATED: Calculate detailed file type statistics with combined categories
Map<String, dynamic> _calculateFileTypeStatsFromFiles(List<Map<String, dynamic>> files) {
  final Map<String, Map<String, dynamic>> typeStats = {};
  int totalSize = 0;

  for (final file in files) {
    final originalType = (file['type'] as String? ?? 'unknown').toLowerCase();
    final size = file['size'] as int? ?? 0;
    
    // COMBINE SIMILAR FILE TYPES INTO CATEGORIES
    String categoryType = _getCombinedFileType(originalType);
    
    totalSize += size;
    
    if (!typeStats.containsKey(categoryType)) {
      typeStats[categoryType] = {
        'count': 0,
        'size': 0,
        'color': _getFileTypeColor(categoryType),
        'icon': _getFileTypeIcon(categoryType),
        'displayName': _getFileTypeDisplayName(categoryType),
      };
    }
    
    typeStats[categoryType]!['count'] = (typeStats[categoryType]!['count'] as int) + 1;
    typeStats[categoryType]!['size'] = (typeStats[categoryType]!['size'] as int) + size;
  }

  return {
    'types': typeStats,
    'totalSize': totalSize,
  };
}

// NEW: Combine similar file types into categories
String _getCombinedFileType(String originalType) {
  switch (originalType) {
    // COMBINE ALL IMAGE TYPES
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'tiff':
    case 'svg':
      return 'images';
    
    // COMBINE ALL DOCUMENT TYPES
    case 'docx':
    case 'doc':
    case 'txt':
    case 'rtf':
      return 'documents';
    
    // COMBINE ALL SPREADSHEET TYPES
    case 'xlsx':
    case 'xls':
    case 'csv':
      return 'spreadsheets';
    
    // COMBINE ALL PRESENTATION TYPES
    case 'pptx':
    case 'ppt':
      return 'presentations';
    
    // COMBINE ALL VIDEO TYPES
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'wmv':
    case 'flv':
      return 'videos';
    
    // COMBINE ALL AUDIO TYPES
    case 'mp3':
    case 'wav':
    case 'flac':
    case 'm4a':
    case 'aac':
      return 'audio';
    
    // COMBINE ALL ARCHIVE TYPES
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
    case 'gz':
      return 'archives';
    
    // COMBINE ALL CODE TYPES
    case 'js':
    case 'ts':
    case 'dart':
    case 'py':
    case 'java':
    case 'cpp':
    case 'c':
    case 'html':
    case 'css':
    case 'json':
    case 'xml':
      return 'code';
    
    // KEEP PDF SEPARATE (it's important enough)
    case 'pdf':
      return 'pdf';
    
    // EVERYTHING ELSE
    default:
      return 'other';
  }
}

// UPDATED: Get color for combined file types
Color _getFileTypeColor(String type) {
  switch (type) {
    case 'images':
      return const Color(0xFF10B981); // Green for all images
    case 'pdf':
      return const Color(0xFFEF4444); // Red for PDFs
    case 'documents':
      return const Color(0xFF3B82F6); // Blue for documents
    case 'spreadsheets':
      return const Color(0xFF059669); // Emerald for spreadsheets
    case 'presentations':
      return const Color(0xFFF59E0B); // Orange for presentations
    case 'videos':
      return const Color(0xFF8B5CF6); // Purple for videos
    case 'audio':
      return const Color(0xFFEC4899); // Pink for audio
    case 'archives':
      return const Color(0xFF6B7280); // Gray for archives
    case 'code':
      return const Color(0xFF7C3AED); // Violet for code
    case 'other':
      return const Color(0xFF9CA3AF); // Light gray for others
    default:
      return const Color(0xFF9CA3AF);
  }
}

// UPDATED: Get icon for combined file types
IconData _getFileTypeIcon(String type) {
  switch (type) {
    case 'images':
      return Icons.image_rounded; // Single icon for all images
    case 'pdf':
      return Icons.picture_as_pdf_rounded;
    case 'documents':
      return Icons.description_rounded;
    case 'spreadsheets':
      return Icons.table_chart_rounded;
    case 'presentations':
      return Icons.slideshow_rounded;
    case 'videos':
      return Icons.video_file_rounded;
    case 'audio':
      return Icons.audio_file_rounded;
    case 'archives':
      return Icons.folder_zip_rounded;
    case 'code':
      return Icons.code_rounded;
    case 'other':
      return Icons.insert_drive_file_rounded;
    default:
      return Icons.insert_drive_file_rounded;
  }
}

// UPDATED: Get display name for combined file types
String _getFileTypeDisplayName(String type) {
  switch (type) {
    case 'images':
      return 'Images'; // Combined display name
    case 'pdf':
      return 'PDFs';
    case 'documents':
      return 'Documents';
    case 'spreadsheets':
      return 'Spreadsheets';
    case 'presentations':
      return 'Presentations';
    case 'videos':
      return 'Videos';
    case 'audio':
      return 'Audio';
    case 'archives':
      return 'Archives';
    case 'code':
      return 'Code Files';
    case 'other':
      return 'Other';
    default:
      return 'Other';
  }
}

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context,
                  _hasLoadedOnce ? '$_filesStored' : '...',
                  'Files Stored',
                  _hasLoadedOnce 
                    ? _filesStored > 0 
                      ? 'Encrypted & secure' 
                      : 'No files yet'
                    : 'Loading...',
                  const Color(0xFF2563EB),
                  const Color(0xFF0891B2),
                  true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetricCard(
                  context,
                  _hasLoadedOnce 
                    ? _storageUsed < 1 
                      ? '${(_storageUsed * 1024).toStringAsFixed(0)} KB'
                      : '${_storageUsed.toStringAsFixed(1)} MB'
                    : '...',
                  'Storage Used',
                  _hasLoadedOnce 
                    ? _storageUsed > 0 
                      ? 'On IPFS network' 
                      : '0% of unlimited'
                    : 'Loading...',
                  const Color(0xFF0891B2),
                  const Color(0xFF2563EB),
                  false,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // NEW: File Type Breakdown Card
        if (_hasLoadedOnce && _filesStored > 0) ...[
          _buildFileTypeBreakdownCard(context),
          const SizedBox(height: 16),
        ],
        
        _buildWalletBalanceCard(context),
      ],
    );
  }

  // NEW: File Type Breakdown Card
  Widget _buildFileTypeBreakdownCard(BuildContext context) {
    final types = _fileTypeStats['types'] as Map<String, Map<String, dynamic>>? ?? {};
    final totalSize = _fileTypeStats['totalSize'] as int? ?? 0;
    
    if (types.isEmpty) return const SizedBox.shrink();

    // Sort types by size (largest first)
    final sortedTypes = types.entries.toList()
      ..sort((a, b) => (b.value['size'] as int).compareTo(a.value['size'] as int));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2563EB).withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.pie_chart_rounded,
                  size: 18,
                  color: Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Storage Breakdown',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Progress bar showing file type distribution
          Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.05),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Row(
                children: sortedTypes.map((entry) {
                  final size = entry.value['size'] as int;
                  final percentage = totalSize > 0 ? size / totalSize : 0.0;
                  final color = entry.value['color'] as Color;
                  
                  return Expanded(
                    flex: (percentage * 100).round().clamp(1, 100),
                    child: Container(
                      height: 8,
                      color: color,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // File type list
          ...sortedTypes.take(4).map((entry) {
            final typeData = entry.value;
            final size = typeData['size'] as int;
            final count = typeData['count'] as int;
            final color = typeData['color'] as Color;
            final icon = typeData['icon'] as IconData;
            final displayName = typeData['displayName'] as String;
            final percentage = totalSize > 0 ? (size / totalSize * 100) : 0.0;
            
            String formattedSize;
            if (size < 1024) {
              formattedSize = '$size B';
            } else if (size < 1024 * 1024) {
              formattedSize = '${(size / 1024).toStringAsFixed(1)} KB';
            } else {
              formattedSize = '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
            }
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      icon,
                      size: 14,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context).colorScheme.onSurface,
                            letterSpacing: -0.1,
                          ),
                        ),
                        Text(
                          '$count ${count == 1 ? 'file' : 'files'}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formattedSize,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
          
          // Show more indicator if there are more than 4 types
          if (sortedTypes.length > 4)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '+ ${sortedTypes.length - 4} more file ${sortedTypes.length - 4 == 1 ? 'type' : 'types'}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Keep all your existing methods (_buildMetricCard, _buildWalletBalanceCard, etc.)
  Widget _buildMetricCard(
    BuildContext context,
    String value,
    String title,
    String subtitle,
    Color startColor,
    Color endColor,
    bool showTrend,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [startColor, endColor],
          stops: const [0.0, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: startColor.withOpacity(0.15),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          if (showTrend)
            Container(
              constraints: const BoxConstraints(maxWidth: double.infinity),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    !_hasLoadedOnce 
                      ? Icons.hourglass_empty_rounded
                      : _filesStored > 0 
                        ? Icons.security_rounded 
                        : Icons.folder_outlined,
                    size: 12,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.9),
                        letterSpacing: -0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.white.withOpacity(0.8),
                letterSpacing: -0.1,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
        ],
      ),
    );
  }

  Widget _buildWalletBalanceCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected 
            ? const Color.fromARGB(255, 8, 11, 10).withOpacity(0.2)
            : const Color(0xFF2563EB).withOpacity(0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isConnected ? 'Wallet Connected' : 'No Wallet Connected',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isConnected ? const Color(0xFF10B981) : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isConnected ? 'Session Active' : 'Session Inactive',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: _isConnected ? const Color(0xFF10B981) : Colors.orange,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _networkName,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    letterSpacing: -0.1,
                  ),
                ),
                if (_walletAddress.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${_walletAddress.substring(0, 6)}...${_walletAddress.substring(_walletAddress.length - 4)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          const SizedBox(width: 16),
          
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected 
                ? const Color(0xFF10B981).withOpacity(0.1)
                : const Color(0xFF2563EB).withOpacity(0.08),
              border: Border.all(
                color: _isConnected 
                  ? const Color(0xFF10B981).withOpacity(0.2)
                  : const Color(0xFF2563EB).withOpacity(0.15),
                width: 1,
              ),
            ),
            child: Icon(
              _isConnected 
                ? Icons.account_balance_wallet_rounded
                : Icons.wallet_outlined,
              size: 24,
              color: _isConnected 
                ? const Color(0xFF10B981)
                : const Color(0xFF2563EB),
            ),
          ),
        ],
      ),
    );
  }
}
