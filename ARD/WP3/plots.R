#===============================================================================
#       Load libraries
#===============================================================================

library(DESeq2)
library(BiocParallel)
library(data.table)
library(tidyverse)
library(gtable)
library(gridExtra)
library(devtools)
library(Biostrings)
library(vegan)
library(lmPerm)
library(phyloseq)
library(ape)
library(outliers)
library(metacoder)

register(MulticoreParam(12))
#install_github("eastmallingresearch/Metabarcoding_pipeline/scripts")
library(metafuncs)
#load_all("~/pipelines/metabarcoding/scripts/myfunctions")
environment(plot_ordination) <- environment(ordinate) <- environment(plot_richness) <- environment(phyloseq::ordinate)
environment(calc_taxon_abund) <- environment(metacoder::calc_taxon_abund) #This is for a bug fix, though there is an updated version of metacoder which fixes this.

#===============================================================================
#       Load data
#===============================================================================

# takes a while to load all the data..
# therefore I've saved the data as r objects:
attach("ubiom_BAC.bin")
attach("ubiom_FUN.bin")

#===============================================================================
#       Attach objects
#===============================================================================

# attach objects (FUN, BAC,OO or NEM)
invisible(mapply(assign, names(ubiom_FUN), ubiom_FUN, MoreArgs=list(envir = globalenv())))
invisible(mapply(assign, names(ubiom_BAC), ubiom_BAC, MoreArgs=list(envir = globalenv())))

#===============================================================================
#       Pool Data/subsample
#===============================================================================

# remove samples with low counts
dds <- dds[,colSums(counts(dds))>1000]

# There are only 3 (out of 900) missing samples - subsampling is a bit too extreme
# As each sample point has three biological replicates will take the mean of other samples to represent missing samples

# get number of samples per tree
sample_numbers <- table(sub("[A-Z]$","",rownames(colData(dds))))

# collapse (sum) samples
dds <- collapseReplicates(dds,groupby=sub("[A-Z]$","",rownames(colData(dds))))

# set the dds sizefactor to the number of samples
dds$sizeFactor <- as.vector(sample_numbers/3)

# recreate countData and colData
countData<- round(counts(dds,normalize=T),0)
colData <- as.data.frame(colData(dds))

# new dds object with the corrected data set
dds <- DESeqDataSetFromMatrix(countData,colData,~1)

# add back collapsed dds to ubiom objects
# ubiom_BAC$cdds <- dds; ubiom_FUN$cdds <- dds;

# calculate size factors - use Rlog rathern an vst for graphs due to disparity between 
sizeFactors(dds) <-sizeFactors(estimateSizeFactors(dds))
# calcNormFactors(counts(dds),method="RLE",lib.size=(prop.table(colSums(counts(dds)))))

dds$site       <- substr(colnames(dds),1,1)
dds$loc_factor <- as.factor(dds$meters)
dds$time       <- as.factor(dds$time)
dds$block      <- as.factor(dds$block)

list_dds <-list(all     = dds,
		cider   = dds[,dds$site=="H"],
		dessert = dds[,dds$site=="G"],
		c_tree  = dds[,dds$site=="H"&dds$condition=="Y"],
		c_grass = dds[,dds$site=="H"&dds$condition=="N"],
		d_tree  = dds[,dds$site=="G"&dds$condition=="Y"],
		d_grass = dds[,dds$site=="G"&dds$condition=="N"])

#===============================================================================
#      Remove G16 from cider orchard (all trees dead) + control samples
#===============================================================================

		 
list_dds <- lapply(list_dds, function(dds) {
	dds <- dds[,(dds$site=="G")|(dds$site=="H"&dds$genotype_name!="G16")]
	dds$genotype_name <- droplevels(dds$genotype_name)
	dds
})

# rename treatment levels	
list_dds <- lapply(list_dds,function(dds) {
  levels(dds$condition) <- c("Control","Grass aisle","Tree station")
	dds
})
  
# remove control 
list_dds <- lapply(list_dds,function(dds) {
	dds <- dds[,dds$condition!="Control"]
	dds$condition <- droplevels(dds$condition)
	dds$genotype_name <- droplevels(dds$genotype_name)
	dds$time <- droplevels(dds$time)
	dds
})

# and t0  samples (if required)
list_dds <- lapply(list_dds,function(dds) {
	dds <- dds[,dds$time!="0"]
	dds$condition <- droplevels(dds$condition)
	dds$genotype_name <- droplevels(dds$genotype_name)
	dds$time <- droplevels(dds$time)
	dds
})
#===============================================================================
#       Alpha diversity analysis - RUN BEFORE FILTERING OUT ANY LOW COUNT OTUS
#===============================================================================

## BOX plots ##

alpha_limit <- function(g1,limits=c(0,2500),p=2,l=17) {
  g2 <- g1 + coord_cartesian(y=limits)
  g1 <- ggplotGrob(g1)
  g2 <- ggplotGrob(g2)
  g1[["grobs"]][[p]] <- g2[["grobs"]][[p]]
  g1[["grobs"]][[l]] <- g2[["grobs"]][[l]]
  g1
}

legend <- cowplot::get_legend(plot_alpha(counts(list_dds$cider,normalize=T),colData(list_dds$cider),colour="condition",design="time",measures=c("Chao1", "Shannon", "Simpson","Observed"),returnData = F,cbPalette = T,type = "box",legend = "bottom")+
  theme(legend.position ="bottom",legend.justification = "left",legend.title = element_blank(),legend.text=element_text(size=11)))

FUN_cider_boxplot <- plot_alpha(counts(list_dds$cider,normalize=T),colData(list_dds$cider),colour="condition",design="time",measures=c("Chao1", "Shannon", "Simpson","Observed"),returnData = F,cbPalette = T,type = "box",legend="none")
FUN_dessert_boxplot <- plot_alpha(counts(list_dds$dessert,normalize=T),colData(list_dds$dessert),colour="condition",design="time",measures=c("Chao1", "Shannon", "Simpson","Observed"),returnData = F,cbPalette = T,type = "box",legend="none")
BAC_cider_boxplot <- plot_alpha(counts(list_dds$cider,normalize=T),colData(list_dds$cider),colour="condition",design="time",measures=c("Chao1", "Shannon", "Simpson","Observed"),returnData = F,cbPalette = T,type = "box",legend="none")
BAC_dessert_boxplot <- plot_alpha(counts(list_dds$dessert,normalize=T),colData(list_dds$dessert),colour="condition",design="time",measures=c("Chao1", "Shannon", "Simpson","Observed"),returnData = F,cbPalette = T,type = "box",legend="none")

#leg <- metafuncs::ggplot_legend(FUN_cider_boxplot)

FUN_cider_boxplot <- FUN_cider_boxplot + xlab(" ") + theme_classic_thin() %+replace% 
  theme(panel.border = element_rect(colour = "black", fill = NA, size = 0.5),legend.position = "none")

FUN_dessert_boxplot <- FUN_dessert_boxplot +  ylab(" ") + xlab(" ") + theme_classic_thin() %+replace% 
  theme(panel.border = element_rect(colour = "black", fill = NA, size = 0.5),legend.position = "none")

BAC_cider_boxplot <- BAC_cider_boxplot + xlab("Time point") +  theme_classic_thin() %+replace% 
  theme(panel.border = element_rect(colour = "black", fill = NA, size = 0.5),legend.position = "none")

BAC_dessert_boxplot <- BAC_dessert_boxplot +  ylab(" ") + xlab("Time point") + theme_classic_thin() %+replace% 
  theme(panel.border = element_rect(colour = "black", fill = NA, size = 0.5),legend.position = "none")

prow <- plot_grid(alpha_limit(FUN_cider_boxplot,limits = c(500,2500)),
          alpha_limit(FUN_dessert_boxplot,limits = c(500,4000)),
          alpha_limit(BAC_cider_boxplot,limits = c(500,20000)),
          alpha_limit(BAC_dessert_boxplot,limits = c(500,20000)),
          labels = "AUTO"
)
ggsave("ALPHA_BOXPLOT.pdf",plot_grid( prow, legend, ncol = 1, rel_heights = c(1, .08)))



# plot alpha diversity - plot_alpha will convert normalised abundances to integer values
ggsave(paste(RHB,"Alpha_all.pdf",sep="_"),plot_alpha(counts(list_dds$all,normalize=T),colData(list_dds$all),colour="site",design="time",measures=c("Chao1", "Shannon", "Simpson","Observed"),limits=c(0,5000,"Chao1")))
ggsave(paste(RHB,"Alpha_cider.pdf",sep="_"),plot_alpha(counts(list_dds$cider,normalize=T),colData(list_dds$cider),colour="condition",design="time",measures=c("Chao1", "Shannon", "Simpson","Observed"),limits=c(0,5000,"Chao1")))
ggsave(paste(RHB,"Alpha_dessert.pdf",sep="_"),plot_alpha(counts(list_dds$dessert,normalize=T),colData(list_dds$dessert),colour="condition",design="time",measures=c("Chao1", "Shannon", "Simpson","Observed"),limits=c(0,5000,"Chao1")))
ggsave(paste(RHB,"Alpha_c_tree.pdf",sep="_"),plot_alpha(counts(list_dds$c_tree,normalize=T),colData(list_dds$c_tree),design="genotype_name",colour="time",discrete=T,measures=c("Chao1", "Shannon", "Simpson","Observed"),limits=c(0,5000,"Chao1")))
ggsave(paste(RHB,"Alpha_c_grass.pdf",sep="_"),plot_alpha(counts(list_dds$c_grass,normalize=T),colData(list_dds$c_grass),design="genotype_name",colour="time",discrete=T,measures=c("Chao1", "Shannon", "Simpson","Observed"),limits=c(0,5000,"Chao1")))
ggsave(paste(RHB,"Alpha_d_tree.pdf",sep="_"),plot_alpha(counts(list_dds$d_tree,normalize=T),colData(list_dds$d_tree),design="genotype_name",colour="time",discrete=T,measures=c("Chao1", "Shannon", "Simpson","Observed"),limits=c(0,5000,"Chao1")))
ggsave(paste(RHB,"Alpha_d_grass.pdf",sep="_"),plot_alpha(counts(list_dds$d_grass,normalize=T),colData(list_dds$d_grass),design="genotype_name",colour="time",discrete=T,measures=c("Chao1", "Shannon", "Simpson","Observed"),limits=c(0,5000,"Chao1")))

#===============================================================================
#       Filter data
#===============================================================================

# filter count data
list_dds <- lapply(list_dds,function(dds) {dds[rowSums(counts(dds, normalize=T))>4,]})

# filter taxonomy data
list_taxData <- lapply(list_dds,function(dds) {taxData[rownames(dds),]})

#===============================================================================
#       Microbial Populations
#===============================================================================


### phylum level population frequency ###
sink(paste0(RHB,"_Phylum_Frequencies_v2.txt"))
 cat("# Dessert Orchard frequencies at phylum rank\n")
 cat("# Overall\n")
 sumTaxa(list(as.data.frame(counts(list_dds$dessert,normalize=T)),taxData,list_dds$dessert@colData),conf=0.8,design="all",proportional=T)
 cat("# By time point\n")
 sumTaxa(list(as.data.frame(counts(list_dds$dessert,normalize=T)),taxData,list_dds$dessert@colData),conf=0.8,design="time",proportional=T)
 cat("# By genotype\n")
 sumTaxa(list(as.data.frame(counts(list_dds$dessert,normalize=T)),taxData,list_dds$dessert@colData),conf=0.8,design="genotype_name",proportional=T)
 cat("# By time point and condition\n")
 sumTaxa(list(as.data.frame(counts(list_dds$dessert,normalize=T)),taxData,list_dds$dessert@colData),conf=0.8,design=c("condition","time"),proportional=T)
 cat("# By time point and genotype\n")
 sumTaxa(list(as.data.frame(counts(list_dds$dessert,normalize=T)),taxData,list_dds$dessert@colData),conf=0.8,design=c("genotype_name","time"),proportional=T)
 cat("# By time point,condition and genotype\n")
 sumTaxa(list(as.data.frame(counts(list_dds$dessert,normalize=T)),taxData,list_dds$dessert@colData),conf=0.8,design=c("genotype_name","condition","time"),proportional=T)
 cat("\n\n# Cider Orchard frequenciea at phylum rank\n")
 cat("# Overall\n")
 sumTaxa(list(as.data.frame(counts(list_dds$cider,normalize=T)),taxData,list_dds$cider@colData),conf=0.8,design="all",proportional=T)
 cat("# By time point\n")
 sumTaxa(list(as.data.frame(counts(list_dds$cider,normalize=T)),taxData,list_dds$cider@colData),conf=0.8,design="time",proportional=T)
 cat("# By genotype\n")
 sumTaxa(list(as.data.frame(counts(list_dds$cider,normalize=T)),taxData,list_dds$cider@colData),conf=0.8,design="genotype_name",proportional=T)
 cat("# By time point and condition\n")
 sumTaxa(list(as.data.frame(counts(list_dds$cider,normalize=T)),taxData,list_dds$cider@colData),conf=0.8,design=c("condition","time"),proportional=T)
 cat("# By time point and genotype\n")
 sumTaxa(list(as.data.frame(counts(list_dds$dessert,normalize=T)),taxData,list_dds$dessert@colData),conf=0.8,design=c("genotype_name","time"),proportional=T)
 cat("# By time point,condition and genotype\n")
 sumTaxa(list(as.data.frame(counts(list_dds$cider,normalize=T)),taxData,list_dds$cider@colData),conf=0.8,design=c("genotype_name","condition","time"),proportional=T)
sink()

## Phylum plots##

melt_func <- function(dds) {
	md2 <- melt(sumTaxaAdvanced(list(as.data.frame(counts(dds,normalize=T)),taxData,dds@colData),conf=0.9,design=c("condition","time"),proportional=T,others=T,cutoff=1))
	md2$Condition <-  unlist(strsplit(as.character(md2[,2])," : "))[c(T,F)]
	md2$TimePoint <-  unlist(strsplit(as.character(md2[,2])," : "))[c(F,T)]
	md2$TimePoint <- as.integer(md2$TimePoint)
	md2$Condition <- as.factor(md2$Condition)
	md2$phylum <- factor(md2$phylum,aggregate(md2$value,by=list(md2$phylum),mean)[order(aggregate(md2$value,by=list(md2$phylum),mean)[,2],decreasing=T),][,1])
	md2
}

line_plot <- function(md2,legend="none") {
	g <- ggplot(md2,aes(x=TimePoint,y=value,colour=Condition,phylum=phylum))
	g <- g + geom_smooth() + scale_x_continuous(breaks=c(0,1,2))
	g <- g + scale_colour_manual(values = c("Grass aisle" = "black", "Tree station" = "orange"))
	g <- g + facet_wrap(~phylum)
	g <- g +theme_classic_thin() %+replace% theme(
		panel.border = element_rect(colour = "black", fill=NA, size=0.5),
		#axis.title = element_blank(),
		legend.position=legend
	)
	g
}

lab <- get_legend(line_plot(melt_func(list_dds$cider),"right"))
g1 <- line_plot(melt_func(list_dds$cider)) + ylab("Abundance(%)") + xlab("")
g2 <- line_plot(melt_func(list_dds$dessert)) + ylab("Abundance(%)") + xlab("TimePoint")
ggsave(paste(RHB,"frequency_plot_o_y_v2.pdf",sep="_"),plot_grid(
plot_grid(g1,g2,nrow=2,labels="AUTO",rel_heights=c(0.4,0.6)),
leg,ncol = 2, rel_widths = c(1, .2))
      , height=7.5)


# bar plot
g <- ggplot(md2,aes(x=phylum,y=value,fill=Condition))
g <- g + geom_bar(stat = "identity", position = "dodge") + scale_fill_manual(values = c("Grass aisle" = "black", "Tree station" = "orange"))
g <- g + facet_wrap(~TimePoint,ncol=1)
leg <- get_legend(g)

g1u <- g + theme_facet_blank(angle=45,t=-25,hjust=1) %+replace% theme(
	plot.margin = unit(c(0.2,0.2,1.5,1.5), "cm"), 
	axis.title = element_blank(),
	legend.position="none"
)

gt <- grid.arrange(plot_grid(g1u,g2u,labels="AUTO"),leg,layout_matrix=cbind(1,1,1,1,1,2),left="Abundance(%)")
test <- grid.arrange(g1u,left="Abundance(%)")
gt <- grid.arrange(plot_grid(test,g2u,labels="AUTO"),leg,layout_matrix=cbind(1,1,1,1,1,2))

ggsave(paste(RHB,"phylum_freq.pdf",sep="_"),gt)

# Genotype plots #
### FUNGI ONLY ###		       
md <- melt(sumTaxa(list(as.data.frame(counts(dds,normalize=T)),taxData,dds@colData),conf=0.8,design=c("genotype_name","condition","time"),proportional=T))
### BACTERIA (REMOVING LOW ABUNDANCE PHYLA) ONLY###
X  <- sumTaxa(list(as.data.frame(counts(dds,normalize=T)),taxData,dds@colData),conf=0.8,design=c("genotype_name","condition","time"),proportional=F)
X$phylum <- sub("candidate_division_","*cd ",X$phylum)
md <- melt(X[apply(X[-1],1,max)>1.1,])
rm(X)
### END ALTERNATIVE ###

md$Genotype  <-  unlist(strsplit(as.character(md[,2])," : "))[c(T,F,F)]
md$Condition <-  unlist(strsplit(as.character(md[,2])," : "))[c(F,T,F)]
md$TimePoint <-  unlist(strsplit(as.character(md[,2])," : "))[c(F,F,T)]

md$Condition[md$Condition=="N"] <- "Grass Alley"
md$Condition[md$Condition=="Y"] <- "Tree Station"
md$Condition[md$Condition=="C"] <- "Control"

md$Genotype  <- as.factor(md$Genotype)
md$Condition <- as.factor(md$Condition)

md$phylum <- factor(md$phylum,aggregate(md$value,by=list(md$phylum),mean)[order(aggregate(md$value,by=list(md$phylum),mean)[,2],decreasing=T),][,1])


#### Weigthed mean difference plots ####
### FUNGI ONLY ###		       
md <- melt(sumTaxa(list(as.data.frame(counts(dds,normalize=T)),taxData,dds@colData),conf=0.8,design=c("genotype_name","condition","time"),proportional=F,meanDiff=T))
### BACTERIA (REMOVING LOW ABUNDANCE PHYLA) ###
X  <- sumTaxa(list(as.data.frame(counts(dds,normalize=T)),taxData,dds@colData),conf=0.8,design=c("genotype_name","condition","time"),proportional=F,meanDiff=T)
X$phylum <- sub("candidate_division_","*cd ",X$phylum)
md <- melt(X[apply(X[-1],1,max)>0.55,])
rm(X)
### END ALTERNATIVE ###

md$Genotype  <-  unlist(strsplit(as.character(md[,2]),"\\.+"))[c(T,F,F,F,F,F)]
md$Condition <-  unlist(strsplit(as.character(md[,2]),"\\.+"))[c(F,T,F,F,F,F)]
md$TimePoint <-  unlist(strsplit(as.character(md[,2]),"\\.+"))[c(F,F,T,F,F,F)]
md$Genotype_2  <-  unlist(strsplit(as.character(md[,2]),"\\.+"))[c(F,F,F,T,F,F)]
md$Condition_2 <-  unlist(strsplit(as.character(md[,2]),"\\.+"))[c(F,F,F,F,T,F)]
md$TimePoint_2 <-  unlist(strsplit(as.character(md[,2]),"\\.+"))[c(F,F,F,F,F,T)]
md <- md[(md$Genotype==md$Genotype_2)&(md$TimePoint==md$TimePoint_2),]

# calculate "relative" values (% abundance of each phyla at each time point)
md$tp_size <- 0
md$tp_size[md$TimePoint==0] <- sum(md$value[md$TimePoint==0])
md$tp_size[md$TimePoint==1] <- sum(md$value[md$TimePoint==1])
md$tp_size[md$TimePoint==2] <- sum(md$value[md$TimePoint==2])
md$prop <- (md$value/md$tp_size)*100

md$Condition[md$Condition=="N"] <- "Grass Alley"
md$Condition[md$Condition=="Y"] <- "Tree Station"
md$Condition[md$Condition=="C"] <- "Control"

md$Genotype  <- as.factor(md$Genotype)
md$Condition <- as.factor(md$Condition)
md$TimePoint <- as.integer(md$TimePoint)

colnames(md)[c(3,11)] <- c("Absolute","Relative")

pdf(paste(RHB,ORCH,"Weighted_Mean_Difference_abundance.pdf",sep="_"),width=8,height=7)
 g <- ggplot(md,aes(x=TimePoint,phylum=phylum))
 g <- g + geom_smooth(aes(y=Absolute))
 g <- g + scale_x_continuous(breaks=c(0,1,2))
 g <- g + facet_wrap(~phylum,scales="free_y")
 g <- g +  theme_classic_thin() %+replace% theme(panel.border = element_rect(colour = "black", fill=NA, size=0.5))
 g;g %>% remove_geom("smooth",1,"y") + geom_smooth(aes(y=Relative))
dev.off()

pdf(paste(RHB,ORCH,"Weighted_Genotype_mean_difference.pdf"),width=20,height=20)
 g <- g + facet_wrap(Genotype~phylum,scales="free_y")
 g;g %>% remove_geom("smooth",1,"y") + geom_smooth(aes(y=Relative))
dev.off()

#===============================================================================
#       Beta diversity analysis
#===============================================================================

### PCA ###

# perform PC decomposition of DES objects
list_pca <- lapply(list_dds,des_to_pca)

# to get pca plot axis into the same scale create a dataframe of PC scores multiplied by their variance
d <- lapply(list_pca,function(mypca) {t(data.frame(t(mypca$x)*mypca$percentVar))})

#pc.res <- lapply(seq_along(list_pca),function(i) {resid(aov(list_pca[[i]]$x~list_dds[[i]]$loc_factor))})
#dd <- lapply(seq_along(list_pca),function(i) {t(data.frame(t(pc.res[[i]])*list_pca[[i]]$percentVar))})

# time by condition cetroid plots for both orchards and biomes

# centroid plot
centroids <- lapply(seq_along(d),function(i){
	X<-merge(d[[i]],colData(list_dds[[i]])[,c(1,2,9)],by="row.names")
  aggregate(X[,2:(ncol(d[[i]])+1)],b=as.list(X[,(ncol(d[[i]])+2):(ncol(d[[i]])+4)]),mean)})

# all f
g1 <- plotOrd(centroids[[2]][,c(-1,-2,-3)],centroids[[2]][,1:3],design="condition",shape="time",pointSize=1,alpha=0.75,ylims=c(-7,7))# + ggtitle("A")
g2 <- plotOrd(centroids[[3]][,c(-1,-2,-3)],centroids[[3]][,1:3],design="condition",shape="time",pointSize=1,alpha=0.75,ylims=c(-7,7),xlims=c(-10,10))# + ggtitle("B")
# RE-RUN FOR FUN OR BAC
g3 <- plotOrd(centroids[[2]][,c(-1,-2,-3)],centroids[[2]][,1:3],design="condition",shape="time",pointSize=1,alpha=0.75)# + ggtitle("C")
g4 <- plotOrd(centroids[[3]][,c(-1,-2,-3)],centroids[[3]][,1:3],design="condition",shape="time",pointSize=1,alpha=0.75,ylims=c(-4,4))# + ggtitle("D")


gleg <- get_legend(g4+theme(legend.position="bottom", legend.box = "vertical",legend.justification="left",legend.box.just="left"))#, plot.margin=unit(c(-2,0,-1,0), "cm")))  
g1u <- g1 +  theme_classic_thin() %+replace% theme(legend.position="none",axis.title.x=element_blank())#,plot.margin=unit(c(0.5,0.5,-1,0.5), "cm"))
g2u <- g2 + ylab("") +  theme_classic_thin() %+replace% theme(legend.position="none",axis.title.x=element_blank())#,plot.margin=unit(c(0.5,0.5,-1,0.5), "cm"))
g3u <- g3 +  theme_classic_thin() %+replace% theme(legend.position="none")#,plot.margin=unit(c(-1,0.5,-2,0.5), "cm")) 
g4u <- g4 + ylab("") + theme_classic_thin() %+replace% theme(legend.position="none")#, plot.margin=unit(c(-1,0.5,-2,0.5), "cm")) 

plot_grid(g1u,g2u,g3u,g4u,nrow=2,labels="AUTO")
ggsave("test.pdf",plot_grid(
	plot_grid(g1u,g3u,nrow=2,labels=c("A","C"),rel_heights=c(1,0.5)),
	plot_grid(g2u,g4u,nrow=2,labels=c("B","D"),rel_heights=c(1,0.5)),
	gleg,nrow=2,rel_heights=c(1,0.2)),height=6)


layout_matrix <- cbind(c(1,1,1,3,3,3,5),c(2,2,2,4,4,4,5))

ggsave("Centroid_PDA_plot.pdf",grid.arrange(g1u,g2u,g3u,g4u,gleg,layout_matrix=layout_matrix),height=5.5)

# !c!t0 plot
attach("PCA.bin") # time point 1 and 2 PCA for BAC and FUN
invisible(mapply(assign, names(obj), obj, MoreArgs=list(envir = globalenv())))

# add condition_time factor to centroid data.frames
BAC_centroids <- lapply(BAC_centroids,function(X) {
	condition_time <- paste(X$condition,X$time,sep=" t")
	cbind(X[,1:3],condition_time,X[,4:ncol(X)])
})
FUN_centroids <- lapply(FUN_centroids,function(X) {
	condition_time <- paste(X$condition,X$time,sep=" t")
	cbind(X[,1:3],condition_time,X[,4:ncol(X)])
})

#reorder genotype levels (G16 to end - then graph colours will match between orchards and can make single plot)
BAC_centroids[[3]]$genotype_name <- factor(BAC_centroids[[3]]$genotype_name, levels=c(
	levels(BAC_centroids[[3]]$genotype_name)[-2],
	levels(BAC_centroids[[3]]$genotype_name)[2]
))
FUN_centroids[[3]]$genotype_name <- factor(FUN_centroids[[3]]$genotype_name, levels=c(
	levels(BAC_centroids[[3]]$genotype_name)[-2],
	levels(BAC_centroids[[3]]$genotype_name)[2]
))

# try with facets????
g1 <- plotOrd(FUN_centroids[[2]][,c(-1,-2,-3,-4)],FUN_centroids[[2]][,1:4],design="genotype_name",
	pointSize=1,axes=c(1,2),alpha=0.75,facet="condition_time",cbPalette=T,ylims=c(-4,4))
g2 <- plotOrd(FUN_centroids[[3]][,c(-1,-2,-3,-4)],FUN_centroids[[3]][,1:4],design="genotype_name",
	pointSize=1,axes=c(1,2),alpha=0.75,facet="condition_time",cbPalette=T,xlims=c(-6,8))
g3 <- plotOrd(BAC_centroids[[2]][,c(-1,-2,-3,-4)],BAC_centroids[[2]][,1:4],design="genotype_name",
	pointSize=1,axes=c(1,2),alpha=0.75,facet="condition_time",cbPalette=T,ylims=c(-6,6.5))
g4 <- plotOrd(BAC_centroids[[3]][,c(-1,-2,-3,-4)],BAC_centroids[[3]][,1:4],design="genotype_name",
	pointSize=1,axes=c(1,2),alpha=0.75,facet="condition_time",cbPalette=T,ylims=c(-5,4))

gleg <- g4 +theme(legend.position="bottom", legend.box = "vertical",legend.justification="left",legend.box.just="left", plot.margin=unit(c(-2,0,-1,0), "cm"))
gleg$guides$colour$title <- "Genotype"
gleg <- get_legend(gleg)  
#gleg_1 <- get_legend(g3+theme(legend.position="bottom", legend.box = "vertical",legend.justification="left",legend.box.just="left", plot.margin=unit(c(-2,0,-1,0), "cm")))  

g1u <- g1 + facet_wrap(facets="facet")+theme_facet_blank(10,angle=0) %+replace% theme(legend.position="none")
g2u <- g2 + facet_wrap(facets="facet")+theme_facet_blank(10,angle=0) %+replace% theme(legend.position="none")
g3u <- g3 + facet_wrap(facets="facet")+theme_facet_blank(10,angle=0) %+replace% theme(legend.position="none")
g4u <- g4 + facet_wrap(facets="facet")+theme_facet_blank(10,angle=0) %+replace% theme(legend.position="none")

# cowplot saves messing around with gtables and adding titles to the right place
library(cowplot)
g <- plot_grid(g1u,g2u,g3u,g4u,labels="AUTO")

# but cowplot can't add single legends
layout_matrix <- rbind(1,1,1,1,1,2)
ggsave("Centroid_genotype_t1_t2.pdf",grid.arrange(g,gleg,layout_matrix=layout_matrix))

# alternative method twith gtable
library(gtable)
g1u <- ggplotGrob(g1u)
g2u <- ggplotGrob(g2u)
g3u <- ggplotGrob(g3u)
g4u <- ggplotGrob(g4u)
gg1 <- rbind(g1u, g3u, size = "first")
#gg1$widths <- unit.pmax(g1u$widths, g3u$widths)
gg2 <- rbind(g2u, g4u, size = "first")
#gg2$widths <- unit.pmax(g2u$widths, g3u$widths)
gg3 = do.call(cbind, c(list(gg1,gg2), size="first"))
grid.arrange(gg3,gleg_1,gleg,layout_matrix=cbind(c(1,1,1,1,1,1,2),c(1,1,1,1,1,1,3)))

layout_matrix <- rbind(c(1,1,1,1,2),c(1,1,1,1,2))

ggsave("Centroid_genotype_cider.pdf",grid.arrange(gg1,gleg_1,layout_matrix=layout_matrix))
ggsave("Centroid_genotype_dessert.pdf",grid.arrange(gg2,gleg,layout_matrix=layout_matrix))





pdf(paste(RHB,"PCA_CENTROIDS_with_controls.pdf",sep="_"))
 #plotOrd(centroids[[1]][,c(-1,-2,-3)],centroids[[1]][,1:3],design="condition",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Both orchards")
 plotOrd(centroids[[2]][,c(-1,-2,-3)],centroids[[2]][,1:3],design="condition",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Cider orchard")
 plotOrd(centroids[[3]][,c(-1,-2,-3)],centroids[[3]][,1:3],design="condition",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Dessert orchard")
 plotOrd(centroids[[2]][,c(-1,-2,-3)],centroids[[2]][,1:3],design="condition",shape="time",pointSize=1.5,axes=c(2,3),alpha=0.75) + ggtitle("Cider orchard")
 plotOrd(centroids[[3]][,c(-1,-2,-3)],centroids[[3]][,1:3],design="condition",shape="time",pointSize=1.5,axes=c(2,3),alpha=0.75) + ggtitle("Dessert orchard")
 plotOrd(centroids[[2]][,c(-1,-2,-3)],centroids[[2]][,1:3],design="condition",shape="time",pointSize=1.5,axes=c(3,4),alpha=0.75) + ggtitle("Cider orchard")
 plotOrd(centroids[[3]][,c(-1,-2,-3)],centroids[[3]][,1:3],design="condition",shape="time",pointSize=1.5,axes=c(3,4),alpha=0.75) + ggtitle("Dessert orchard")
dev.off()


# plot the PCA - need to think about model
pdf(paste(RHB,"PCA.pdf",sep="_"))
 plotOrd(d[[1]],colData(list_dds[[1]]),design="site",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Both orchards")
 plotOrd(d[[2]],colData(list_dds[[2]]),design="condition",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Cider orchard")
 plotOrd(d[[3]],colData(list_dds[[3]]),design="condition",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Dessert orchard")
 plotOrd(d[[4]],colData(list_dds[[4]]),design="genotype_name",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Cider tree station")
 plotOrd(d[[5]],colData(list_dds[[5]]),design="genotype_name",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Cider grass alley")
 plotOrd(d[[6]],colData(list_dds[[6]]),design="genotype_name",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Dessert tree station")
 plotOrd(d[[7]],colData(list_dds[[7]]),design="genotype_name",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Dessert grass alley")
dev.off()

pdf(paste(RHB,"PCA_LOCATION.pdf",sep="_"))
 plotOrd(dd[[1]],colData(list_dds[[1]]),design="site",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Both orchards")
 plotOrd(dd[[2]],colData(list_dds[[2]]),design="condition",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Cider orchard")
 plotOrd(dd[[3]],colData(list_dds[[3]]),design="condition",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Dessert orchard")
 plotOrd(dd[[4]],colData(list_dds[[4]]),design="genotype_name",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Cider tree station")
 plotOrd(dd[[5]],colData(list_dds[[5]]),design="genotype_name",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Cider grass alley")
 plotOrd(dd[[6]],colData(list_dds[[6]]),design="genotype_name",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Dessert tree station")
 plotOrd(dd[[7]],colData(list_dds[[7]]),design="genotype_name",shape="time",pointSize=1.5,axes=c(1,2),alpha=0.75) + ggtitle("Dessert grass alley")
dev.off()



#===============================================================================
#       RDA plots
#===============================================================================

list_vst <- lapply(list_dds,varianceStabilizingTransformation)

# WORK OUT WHAT I WANT TO PLOT FIRST BEFORE WRITING THE CODE!!!!!

# at orchard level - split data by time point, shape by condition, facet by genotype

# agregate counts at phylum level
combinedTaxa <- combineTaxa2(taxData[,-8],rank="phylum",confidence=0.8,returnFull=T)# no longer necessary - lapply(list_taxData,function(taxData) combineTaxa2(taxData[,-8],rank="phylum",confidence=0.8,returnFull=T))
myTaxa <- combTaxa(combinedTaxa,taxData[,-8]) #lapply(seq_along(combinedTaxa),function(i) combTaxa(combinedTaxa[[i]],list_taxData[[i]][,-8]))

qf <- function(dds,combinedTaxa=combinedTaxa,myTaxa=myTaxa,time,formula="~genotype_name",conf=0.8,level=2) {
	dds <- dds[,dds$time%in%time]
	myData <- combCounts(combinedTaxa,assay(dds,normalize=T))
	myData <- aggregate(myData,by=list(taxaConfVec(myTaxa[rownames(myTaxa)%in%rownames(myData),],conf=conf,level=level)),sum)
	rownames(myData) <- myData[,1];
	myData <- myData[,-1]
	rda(formula(paste0("t(myData)",formula)),data=colData(dds))
}

### Genotype plots ###

# rda covering all time points
myrda <- lapply(list_dds,qf,combinedTaxa,myTaxa,c("0","1","2"),"~Condition(block)+time+genotype_name") # not list_vst?

# get scores from rda object
myscores <- lapply(myrda,vegan::scores,scaling="symmetric")

site_centroids <- lapply(seq_along(myscores),function(i){
	X<-merge(myscores[[i]]$sites,colData(list_dds[[i]])[,c(1,2,9)],by="row.names")
  aggregate(X[,2:3],b=as.list(X[,4:6]),mean)})

site_scores <- lapply(seq_along(myscores),function(i){
	ss <- merge(myscores[[i]]$site,colData(list_dds[[i]]),by="row.names")
	ss$m <- as.matrix(ss[,2:3]);return(ss)})

species <- lapply(myscores,function(s) {
	species <- as.data.frame(s$species)
  species$phylum<-rownames(species)
  return(species)})

# filter out phyla which sit next to the axis
species <- lapply(species,function(species){species[(abs(species[,1])>10|abs(species[,2])>10),]})

titles <- c("All","Cider","Dessert","Cider tree","Cider grass","Dessert tree","Dessert grass")

pdf(paste0(RHB,"_phylum_genotype_plots.pdf"))
 lapply(seq_along(site_centroids),function(i)
	plotOrd(site_centroids[[i]][,4:5],site_centroids[[i]][,1:3],design="genotype_name",shape="time",alpha=0.75)+
	ggtitle(titles[i]) +
	geom_segment(data=species[[i]],aes(x=0,y=0,xend=RDA1,yend=RDA2), size=0.5,arrow=arrow(),inherit.aes=F) +
	geom_label(data=species[[i]],aes(label=phylum,x=(RDA1/2),y=(RDA2/2)),size=2,inherit.aes=F))
dev.off()


# agregate counts at class level
combinedTaxa <- combineTaxa2(taxData[,-8],rank="class",confidence=0.75,returnFull=T)# no longer necessary - lapply(list_taxData,function(taxData) combineTaxa2(taxData[,-8],rank="phylum",confidence=0.8,returnFull=T))
myTaxa <- combTaxa(combinedTaxa,taxData[,-8]) #lapply(seq_along(combinedTaxa),function(i) combTaxa(combinedTaxa[[i]],list_taxData[[i]][,-8]))

### Genotype plots ###

# rda covering all time points
myrda <- lapply(list_dds,qf,combinedTaxa,myTaxa,c("0","1","2"),"~Condition(block)+time+genotype_name",0.75,3)

# get scores from rda object
myscores <- lapply(myrda,vegan::scores,scaling="symmetric")

site_centroids <- lapply(seq_along(myscores),function(i){
	X<-merge(myscores[[i]]$sites,colData(list_dds[[i]])[,c(1,2,9)],by="row.names")
  aggregate(X[,2:3],b=as.list(X[,4:6]),mean)})

site_scores <- lapply(seq_along(myscores),function(i){
	ss <- merge(myscores[[i]]$site,colData(list_dds[[i]]),by="row.names")
	ss$m <- as.matrix(ss[,2:3]);return(ss)})

species <- lapply(myscores,function(s) {
	species <- as.data.frame(s$species)
  species$phylum<-rownames(species)
  return(species)})

# filter out phyla which sit next to the axis
species <- lapply(species,function(species) {species[(abs(species[,1])>10|abs(species[,2])>10),]})

pdf(paste0(RHB,"_class_genotype_plots.pdf"))
 lapply(seq_along(site_centroids),function(i)
	plotOrd(site_centroids[[i]][,4:5],site_centroids[[i]][,1:3],design="genotype_name",shape="time",alpha=0.75)+
	ggtitle(titles[i]) +
	geom_segment(data=species[[i]],aes(x=0,y=0,xend=RDA1,yend=RDA2), size=0.5,arrow=arrow(),inherit.aes=F) +
	geom_label(data=species[[i]],aes(label=phylum,x=(RDA1/2),y=(RDA2/2)),size=2,inherit.aes=F))
dev.off()

#===============================================================================
#       Differential analysis - for heat trees
#===============================================================================		  


# (a) M116 Tree_station against M116 aisle, and 
# (b) (M116 Tree_station + [AR295_6 + M26 + G41 + M9] ailse) vs ((M116 Aisle + [AR295_6 + M26 + G41 + M9] tree_station) (interaction effect for M116)

#### (a) ####
dds   <- list_dds[[2]][,list_dds[[2]]$genotype_name=="M116"]

# all time points #
full   <-  ~block + time*condition
reduced <- ~block + condition #remove condition if not interested in the changes at time point 0
design(dds) <- full
dds <- DESeq(dds,parallel=T,reduced=reduced,test="LRT")
# model.matrix(design(dds), colData(dds))
# resultsNames(dds)

# for each time point
results(dds,contrast=c("condition","Tree station","Grass aisle"),test="Wald") # main effect (condition effect for time 0)
res0 <- results(dds,contrast=list(c("condition_Tree.station_vs_Grass.aisle")),test="Wald") # as above, but makes below easier to understand 
res1 <- results(dds,contrast=list(c("condition_Tree.station_vs_Grass.aisle", "time1.conditionTree.station")),test="Wald") # main effect + interaction term for time 1
res2 <- results(dds,contrast=list(c("condition_Tree.station_vs_Grass.aisle", "time2.conditionTree.station")),test="Wald") # main effect + interaction term for time 2

# across timepoints
res <- results(dds)

### (b) ###
# (b) (M116 Tree_station + [AR295_6 + M26 + G41 + M9] ailse) vs ((M116 Aisle + [AR295_6 + M26 + G41 + M9] tree_station)
dds   <- list_dds[[2]]

# filter for low counts - this can affect the FD probability and DESeq2 does apply its own filtering for genes/otus with no power
# but, no point keeping OTUs with 0 -  ah but this can be a problem when doing an LRT test, lots of 0s and a single count can cause the Betas not to converge
dds<-dds[ rowSums(counts(dds,normalize=T))>4,]
# possible filter step - two rows with counts larger than 4
nc <- counts(dds, normalized=TRUE)
filter <- rowSums(nc >= 1) >= 2
dds <- dds[filter,]

dds$condition2 <- as.factor(paste(dds$condition,dds$genotype_name,sep="_"))
dds$condition2 <- relevel(dds$condition2,5)

# models

full    <- ~block + time + time:condition2 
reduced <- ~block + condition2

# design(dds) <- quick
design(dds) <- full
dds <- DESeq(dds,parallel=T)
dds<- DESeq(dds,reduced=reduced,test="LRT",parallel=T)

# get the results
#resultsNames(dds)

# from full design ~ I think this is preferable - technically listValues=c(1/5,-1/5) should be added or the fold changes are 5x too high
res_0 <- results(dds,parallel=T,test="Wald",listValues=c(1/5,-1/5),contrast=list(
	c("time0.condition2Tree.station_M116","time0.condition2Grass.aisle_G41","time0.condition2Grass.aisle_M26", "time0.condition2Grass.aisle_M9", "time0.condition2Grass.aisle_AR295_6"),
	c("time0.condition2Grass.aisle_M116","time0.condition2Tree.station_G41","time0.condition2Tree.station_M26","time0.condition2Tree.station_M9","time0.condition2Tree.station_AR295_6")
))
res_1 <- results(dds,parallel=T,test="Wald",listValues=c(1/5,-1/5),contrast=list(
	c("time1.condition2Tree.station_M116","time1.condition2Grass.aisle_G41", "time1.condition2Grass.aisle_M26", "time1.condition2Grass.aisle_M9", "time1.condition2Grass.aisle_AR295_6"),
	c("time1.condition2Grass.aisle_M116", "time1.condition2Tree.station_G41","time1.condition2Tree.station_M26","time1.condition2Tree.station_M9","time1.condition2Tree.station_AR295_6")
))
res_2 <- results(dds,parallel=T,test="Wald",listValues=c(1/5,-1/5),contrast=list(
	c("time2.condition2Tree.station_M116","time2.condition2Grass.aisle_G41", "time2.condition2Grass.aisle_M26", "time2.condition2Grass.aisle_M9", "time2.condition2Grass.aisle_AR295_6"),
	c("time2.condition2Grass.aisle_M116", "time2.condition2Tree.station_G41","time2.condition2Tree.station_M26","time2.condition2Tree.station_M9","time2.condition2Tree.station_AR295_6")
))	

#===============================================================================
#       Heat tree plots
#===============================================================================
obj <- ubiome_to_taxmap(list(counts(list_dds[[2]],normalize=T),colData(list_dds[[2]]),taxData))
sd <- colData(list_dds[[2]])
sd$c_t <- paste(sd$condition,sd$time,sep="_t")
sd$c_t <- sub("N","grass",sd$c_t)
sd$c_t <- sub("Y","tree",sd$c_t)
sd <- sd[sd$condition!="C",]
tax_abund <- calc_taxon_abund(obj,"otu_table",cols = rownames(sd),groups=sd$c_t)		  
obj$data$tax_prop <- as.tibble(cbind(tax_abund[,1],apply(tax_abund[,-1],2,prop.table),stringsAsFactors=F))
		  
gg0 <-  obj %>% filter_taxa(grass_t0 > 0.001) %>%
  heat_tree(node_label = taxon_names,node_size = grass_t0,node_color = grass_t0,layout = "da", initial_layout = "re")
gg1 <-  obj %>% filter_taxa(grass_t1 > 0.001) %>%
  heat_tree(node_label = taxon_names,node_size = grass_t1,node_color = grass_t1,layout = "da", initial_layout = "re")
gg2 <-  obj %>% filter_taxa(grass_t2 > 0.001) %>%
  heat_tree(node_label = taxon_names,node_size = grass_t2,node_color = grass_t2,layout = "da", initial_layout = "re")
gt0 <-  obj %>% filter_taxa(tree_t0 > 0.001) %>%
  heat_tree(node_label = taxon_names,node_size = tree_t0,node_color = tree_t0,layout = "da", initial_layout = "re")
gt1 <-  obj %>% filter_taxa(tree_t1 > 0.001) %>%
  heat_tree(node_label = taxon_names,node_size = tree_t1,node_color = tree_t1,layout = "da", initial_layout = "re")
gt2 <-  obj %>% filter_taxa(tree_t2 > 0.001) %>%
  heat_tree(node_label = taxon_names,node_size = tree_t2,node_color = tree_t2,layout = "da", initial_layout = "re")

ggsave("cider_big_plot.pdf",grid.arrange(gg0,gg1,gg2,gt0,gt1,gt2,nrow=2),width=12,height=8)		  
		  
