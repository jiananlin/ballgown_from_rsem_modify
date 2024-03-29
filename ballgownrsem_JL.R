## The code is from ballgownrsem at https://github.com/alyssafrazee/ballgown/blob/master/R/ballgownrsem.R
## modified line 47 to line 51



match.data.frame = function(x1, x2, ...){
  match(do.call("paste", c(x1, sep = "\r")),
        do.call("paste", c(x2, sep = "\r")), ...)
}


ballgownrsem_mod = function(dir="", samples, gtf, UCSC=TRUE, tfield='transcript_id',
                        attrsep='; ', bamout='transcript', pData=NULL, verbose=TRUE, meas='all',
                        zipped=FALSE){
  
  bamout = match.arg(bamout, c('transcript', 'genome', 'none'))
  meas = match.arg(meas, c('all', 'TPM', 'FPKM'))
  if('all' %in% meas & length(meas) > 1){
    stop(.makepretty('when meas is "all", all types of measurements are
            included by default.'))
  }
  
  if(verbose){
    message(date())
  }
  
  # transcript/gene correspondence (t2g):
  f = paste0(dir, '/', samples[1], '.isoforms.results')
  if(zipped){
    f = paste0(f, '.gz')
  }
  t2g = read.table(f, header=TRUE, 
                   colClasses=c('character', 'character', rep("NULL", 6)))
  names(t2g) = c('t_id', 'g_id')
  
  
  # exon GRanges setup / e2t:
  if(verbose){
    message(paste0(date(), ': reading annotation'))
  }
  tgtf = gffRead(gtf)
  tgtf$t_name = getAttributeField(tgtf$attributes, tfield, attrsep)
  if(UCSC){
    # strip off extra quotes
    tgtf$t_name = substr(tgtf$t_name, 2, nchar(tgtf$t_name)-1)
  }
  t_id = tgtf$t_name
  uniq_tname = unique(t_id)
  tid_df = data.frame(t_id = uniq_tname,t_idx = seq(1,NROW(uniq_tname),by=1))
  tgtf$t_idx = match(tgtf$t_name,tid_df$t_id)
  tgtf = tgtf[order( tgtf$t_idx, tgtf$start),]
  
  tgtf = tgtf[tgtf$feature == "exon",]
  if(verbose){
    message(paste0(date(), ': handling exons'))
  }
  estrand = as.character(tgtf$strand)
  estrand[estrand=="."] = "*"
  e_id = match.data.frame(tgtf[,c(1,4,5,7)], unique(tgtf[,c(1,4,5,7)])) 
  #^exons id'd by chr, start, end, strand
  t_id = tgtf$t_name
  e2t = data.frame(e_id, t_id)
  tgtf$e_id = e_id
  exons_unique = subset(tgtf, !duplicated(tgtf[,c(1,4,5,7)]))
  
  # exon data frame:
  exon = data.frame(e_id=exons_unique$e_id, chr=exons_unique$seqname,
                    strand=exons_unique$strand, start=exons_unique$start, 
                    end=exons_unique$end)
  exon = exon[order(exon$e_id),] #safety check
  
  # finish exon GRanges:
  tnamesex = split(as.character(e2t$t_id), e2t$e_id)
  #CAREFUL: this ^ is SUPER SLOW if e2t$t_id is left as a factor
  tnamesex_ord = as.character(tnamesex)[match(exon$e_id, names(tnamesex))]
  exongr = GRanges(seqnames=Rle(as.character(exon$chr)), 
                   ranges=IRanges(start=exon$start, end=exon$end), 
                   strand=Rle(exon$strand), 
                   id=exon$e_id, transcripts = tnamesex_ord)
  
  # transcript GRangesList
  if(verbose){
    message(paste0(date(), ': handling introns'))
  }
  
  mm = match(e2t$e_id, mcols(exongr)$id)
  if(any(is.na(mm))){
    warning(paste('the following exon(s) did not appear in the data:',
                  paste(e2t$e_id[which(is.na(mm))], collapse=", ")))
  }
  tgrl = split(exongr[mm[!is.na(mm)]], as.character(e2t$t_id)[!is.na(mm)])
  
  # intron GRanges setup:
  unltrans = unlist(tgrl)
  transcriptIDs = rep(names(tgrl), times=elementNROWS(tgrl))
  notLast = rev(duplicated(rev(transcriptIDs)))
  introngr = GRanges(seqnames=seqnames(unltrans)[notLast], 
                     ranges=IRanges(start=end(unltrans)[notLast]+1, 
                                    end=start(unltrans)[which(notLast)+1]-1), 
                     strand=strand(unltrans)[notLast])
  # same matchymatch trick to identify introns:
  idf = as.data.frame(introngr)
  i_id = match.data.frame(idf, unique(idf))
  mcols(introngr)$id = i_id
  
  # i2t
  i2t = data.frame(i_id, t_id=transcriptIDs[notLast])
  
  # finish intron GRanges:
  tnamesin = split(as.character(i2t$t_id), i2t$i_id) 
  mcols(introngr)$transcripts = as.character(tnamesin)[match(i_id, 
                                                             names(tnamesin))]
  introngr = unique(introngr)
  
  # intron data frame:
  dftmp = IRanges::as.data.frame(introngr)
  stopifnot(all(names(dftmp) == 
                  c('seqnames', 'start', 'end', 'width', 'strand', 'id', 'transcripts')))
  intron = data.frame(i_id=dftmp$id, chr=dftmp$seqnames, strand=dftmp$strand, 
                      start=dftmp$start, end=dftmp$end)
  intron = intron[order(intron$i_id),] #safety check
  
  # transcript data frame
  if(verbose){
    message(paste0(date(), ': handling transcripts'))
  }
  isofiles = paste0(dir, '/', samples, '.isoforms.results')
  if(zipped){
    isofiles = paste0(isofiles, '.gz')
  }
  isodata = lapply(isofiles, function(x){
    read.table(x, header=TRUE)
  })
  gene = isodata[[1]]$gene_id[match(names(tgrl), isodata[[1]]$transcript_id)] 
  trans = data.frame(t_id=names(tgrl), 
                     chr=unlist(runValue(seqnames(tgrl))),
                     strand=unlist(runValue(strand(tgrl))),
                     start=sapply(start(tgrl), min), end=sapply(end(tgrl), max),
                     t_name=names(tgrl), num_exons=elementNROWS(tgrl),
                     length=sapply(width(tgrl), sum), gene_id=gene, gene_name=gene)
  
  for(i in seq_along(isodata)){
    data_order = match(names(tgrl), isodata[[i]]$transcript_id)
    if(meas == 'all' | meas == 'TPM'){
      trans[,paste('TPM', samples[i],  sep='.')] = 
        isodata[[i]]$TPM[data_order]
    }
    if(meas == 'all' | meas == 'FPKM'){
      trans[,paste('FPKM', samples[i], sep='.')] = 
        isodata[[i]]$FPKM[data_order]
    }
  }
  
  # handle pData
  stopifnot(is.null(pData) | class(pData) == 'data.frame')
  if(verbose){
    message(paste0(date(), ': handling pData'))
  }
  
  if(!is.null(pData)){
    if(!all(pData[,1] == samples)){
      msg = 'Rows of pData did not seem to be in the same order as the
                columns of the expression data. Attempting to rearrange
                pData...'
      warning(.makepretty(msg))
      tmp = try(pData <- pData[,match(samples, pData[,1])], 
                silent=TRUE)
      if(class(tmp) == "try-error"){
        msg = 'first column of pData does not match the names of the
                    folders containing the ballgown data.'
        stop(.makepretty(msg))
      }else{
        message('successfully rearranged!')
      }
    }
  }
  
  # handle bamfiles
  if(bamout == 'none'){
    bamfiles=NULL
  }else{
    bamfiles = paste0(dir, '/', samples, '.', bamout, '.bam')
  }
  
  # handle gexpr (get it directly with RSEM)
  genefiles = paste0(dir, '/', samples, '.genes.results')
  if(zipped){
    genefiles = paste0(genefiles, '.gz')
  }
  genedata = lapply(genefiles, function(x){
    read.table(x, header=TRUE)
  })
  g = data.frame(gene_id=sort(genedata[[1]]$gene_id))
  for(i in seq_along(genedata)){
    data_order = match(g$gene_id, genedata[[i]]$gene_id)
    if(meas == 'all' | meas == 'TPM'){
      g[,paste('TPM', samples[i],  sep='.')] = 
        genedata[[i]]$TPM[data_order]
    }
    if(meas == 'all' | meas == 'FPKM'){
      g[,paste('FPKM', samples[i], sep='.')] = 
        genedata[[i]]$FPKM[data_order]
    }
  }
  
  gm = as.matrix(g[,-1])
  rownames(gm) = as.character(g$gene_id)
  colnames(gm) = names(g)[-1]
  rm(g)
  
  result = new("ballgown", 
               expr=list(intron=intron, exon=exon, trans=trans, gm=gm), 
               indexes=list(e2t=e2t, i2t=i2t, t2g=t2g, bamfiles=bamfiles, pData=pData),
               structure=list(intron=introngr, exon=exongr, trans=tgrl), 
               dirs=paste0(normalizePath(dir), '/', samples), 
               mergedDate=date(), meas=meas, RSEM=TRUE)
  
  if(verbose) message(paste0(date(), ': done!'))
  return(result)
}
